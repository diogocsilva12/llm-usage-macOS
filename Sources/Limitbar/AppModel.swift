import AppKit
import Combine
import ServiceManagement
import LimitbarCore

enum ProviderState {
    case disconnected
    case loading
    case loaded(ProviderUsage)
    case failed(String)

    var usage: ProviderUsage? { if case .loaded(let value) = self { return value }; return nil }
    var isLoading: Bool { if case .loading = self { return true }; return false }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var states: [ProviderID: ProviderState] = [:]
    @Published var isPinned = false
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var alertMessage: String?
    @Published private(set) var codexHome: URL
    @Published private(set) var antigravityExecutable: URL?
    @Published private(set) var addedProviders: [ProviderID]
    @Published private(set) var savedCredentials: Set<ProviderID>

    private let preferences: UserDefaults
    private var tasks: [ProviderID: Task<Void, Never>] = [:]
    private var revisions: [ProviderID: UUID] = [:]
    private var timer: AnyCancellable?
    private var wakeObserver: AnyCancellable?

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        addedProviders = ProviderCatalog.restoredProviders(saved: preferences.stringArray(forKey: "addedProviders"),
            previouslyEnabled: ProviderID.allCases.filter { preferences.bool(forKey: "enabled.\($0.rawValue)") })
        savedCredentials = Set(ProviderCatalog.providers.filter { $0.requiresCredential && ProviderKeychain.contains($0.id) }.map(\.id))
        let defaultHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        codexHome = URL(fileURLWithPath: preferences.string(forKey: "codexHome") ?? defaultHome, isDirectory: true)
        antigravityExecutable = preferences.string(forKey: "antigravityExecutable").map { URL(fileURLWithPath: $0) }
        for provider in ProviderID.allCases { states[provider] = .disconnected }
        preferences.set(addedProviders.map(\.rawValue), forKey: "addedProviders")
    }

    func start() {
        refresh()
        timer = Timer.publish(every: 300, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.refresh()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var isRefreshing: Bool { states.values.contains { $0.isLoading } }
    var enabledProviders: [ProviderID] { addedProviders.filter(isEnabled) }
    func isAdded(_ id: ProviderID) -> Bool { addedProviders.contains(id) }
    func isEnabled(_ id: ProviderID) -> Bool { preferences.bool(forKey: "enabled.\(id.rawValue)") }

    func addProvider(_ id: ProviderID) {
        guard !isAdded(id) else { return }
        addedProviders.append(id)
        preferences.set(addedProviders.map(\.rawValue), forKey: "addedProviders")
    }

    func removeProvider(_ id: ProviderID) {
        if ProviderCatalog.definition(for: id).requiresCredential {
            do { try ProviderKeychain.delete(id) }
            catch { alertMessage = (error as? UsageError)?.localizedDescription; return }
            savedCredentials.remove(id)
        }
        setEnabled(false, for: id)
        addedProviders.removeAll { $0 == id }
        preferences.set(addedProviders.map(\.rawValue), forKey: "addedProviders")
    }

    @discardableResult
    func saveCredential(_ token: String, provider: ProviderID) -> Bool {
        do {
            try ProviderKeychain.save(token, provider: provider)
            savedCredentials.insert(provider)
            setEnabled(true, for: provider)
            return true
        } catch {
            alertMessage = (error as? UsageError)?.localizedDescription ?? "Couldn't save the credential."
            return false
        }
    }

    func setEnabled(_ enabled: Bool, for id: ProviderID) {
        if enabled { addProvider(id) }
        preferences.set(enabled, forKey: "enabled.\(id.rawValue)")
        tasks[id]?.cancel()
        tasks[id] = nil
        revisions[id] = UUID()
        states[id] = .disconnected
        if enabled { refresh(id) }
    }

    func refresh() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        for id in enabledProviders { refresh(id) }
    }

    func refresh(_ id: ProviderID) {
        guard isEnabled(id), states[id]?.isLoading != true else { return }
        let revision = UUID()
        revisions[id] = revision
        states[id] = .loading
        let settings = SourceSettings(codexHome: codexHome, antigravityExecutable: antigravityExecutable)
        tasks[id] = Task { [weak self] in
            do {
                let usage = try await ProviderService.fetch(id, settings: settings)
                guard !Task.isCancelled, self?.revisions[id] == revision else { return }
                self?.states[id] = .loaded(usage)
            } catch {
                guard !Task.isCancelled, self?.revisions[id] == revision else { return }
                let message = (error as? UsageError)?.localizedDescription ?? "Couldn't read usage. Check the connection and retry."
                self?.states[id] = .failed(message)
            }
            if self?.revisions[id] == revision { self?.tasks[id] = nil }
        }
    }

    func setCodexHome(_ url: URL) {
        codexHome = url
        preferences.set(url.path, forKey: "codexHome")
        setEnabled(true, for: .codex)
    }

    func setAntigravityExecutable(_ url: URL?) {
        antigravityExecutable = url
        preferences.set(url?.path, forKey: "antigravityExecutable")
        setEnabled(true, for: .antigravity)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            alertMessage = "Build Limitbar.app and move it to Applications before enabling Open at Login."
            return
        }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled, SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            alertMessage = "Couldn't change login settings. Move Limitbar.app to Applications, reopen it, and try again."
        }
    }

    func stop() { tasks.values.forEach { $0.cancel() }; timer = nil; wakeObserver = nil }
}
