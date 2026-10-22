import AppKit
import Combine
import SwiftUI
import LimitbarCore

@main
enum LimitbarApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var hostingController: NSHostingController<UsagePanel>!
    private var connectionsWindow: NSWindow?
    private var observers = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        hostingController = NSHostingController(rootView: UsagePanel(model: model, openConnections: { [weak self] in
            self?.showConnections()
        }))
        popover.contentViewController = hostingController
        model.$states.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateStatus() }.store(in: &observers)
        model.$isPinned.sink { [weak self] pinned in self?.popover.behavior = pinned ? .applicationDefined : .transient }.store(in: &observers)
        model.objectWillChange.debounce(for: .milliseconds(50), scheduler: RunLoop.main).sink { [weak self] in
            self?.resizePanel()
        }.store(in: &observers)
        updateStatus()
        model.start()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            showConnections()
        }
    }

    func applicationWillTerminate(_ notification: Notification) { model.stop() }

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        resizePanel()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func resizePanel() {
        hostingController.view.layoutSubtreeIfNeeded()
        let size = hostingController.view.fittingSize
        popover.contentSize = NSSize(width: PanelStyle.width, height: size.height)
    }

    private func updateStatus() {
        let summaries = model.enabledProviders.map { id -> (ProviderID, String) in
            let text: String
            switch model.states[id] ?? .disconnected {
            case .loaded(let usage): text = usage.summary?.percentage ?? "—"
            case .loading: text = "···"
            case .failed: text = "!"
            case .disconnected: text = "—"
            }
            return (id, text)
        }
        statusItem.button?.title = ""
        statusItem.button?.image = ProviderArtwork.menuBarImage(summaries: summaries)
        statusItem.button?.toolTip = model.enabledProviders.isEmpty ? "Limitbar · Add a provider in Connections" : "Limitbar · " + model.enabledProviders.map(\.title).joined(separator: ", ")
        statusItem.button?.setAccessibilityLabel("Limitbar. " + model.enabledProviders.map { id in
            "\(id.title): \(model.states[id]?.usage?.summary?.percentage ?? "unavailable")"
        }.joined(separator: ", "))
    }

    @objc private func showConnections() {
        popover.performClose(nil)
        if connectionsWindow == nil {
            let controller = NSHostingController(rootView: ConnectionsView(model: model))
            let window = NSWindow(contentViewController: controller)
            window.title = "Limitbar · Connections"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            connectionsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        connectionsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func refresh() { model.refresh() }

    private func installMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let menu = NSMenu()
        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        let connections = NSMenuItem(title: "Connections…", action: #selector(showConnections), keyEquivalent: ",")
        connections.target = self
        menu.addItem(connections)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Limitbar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = menu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }
}
