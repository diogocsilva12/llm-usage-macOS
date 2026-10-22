import AppKit
import SwiftUI
import LimitbarCore

@MainActor
struct ConnectionsView: View {
    @ObservedObject var model: AppModel
    @State private var selected: ProviderID = .codex
    @State private var search = ""

    private var providers: [ProviderDefinition] {
        ProviderCatalog.providers.filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                || $0.summary.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connections").font(.system(size: 21, weight: .semibold))
                TextField("Find a provider", text: $search).textFieldStyle(.roundedBorder)
                Text("PROVIDER CATALOG").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(providers) { provider in
                            HStack(spacing: 6) {
                                Button { selected = provider.id } label: {
                                    HStack(spacing: 9) {
                                        ProviderMark(id: provider.id).frame(width: 19, height: 19)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(provider.title).font(.system(size: 12, weight: .semibold))
                                            Text(provider.authenticationLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                if model.isAdded(provider.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                        .help("Added to your providers")
                                } else {
                                    Button {
                                        selected = provider.id
                                        model.addProvider(provider.id)
                                    } label: { Image(systemName: "plus") }
                                    .buttonStyle(.borderless).help("Add \(provider.title)")
                                    .accessibilityLabel("Add \(provider.title)")
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(selected == provider.id ? Color.accentColor.opacity(0.13) : Color.clear))
                        }
                        if providers.isEmpty { Text("No providers found").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 15) }
                    }
                }
                Spacer(minLength: 0)
                Text("Limitbar \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }.padding(20).frame(width: 255)
            Divider()
            ProviderSetupView(model: model, provider: ProviderCatalog.definition(for: selected))
                .id(selected).padding(26).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 780, height: 610)
        .onAppear { selected = model.addedProviders.first ?? .codex }
        .alert("Limitbar", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK") { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
    }
}

@MainActor
private struct ProviderSetupView: View {
    @ObservedObject var model: AppModel
    let provider: ProviderDefinition
    @State private var credential = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ProviderMark(id: provider.id).frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.title).font(.system(size: 22, weight: .semibold))
                    Text(provider.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(provider.instructions).font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Link("Open provider website ↗", destination: provider.website).font(.system(size: 12))
                    if model.isAdded(provider.id) {
                        if provider.requiresCredential { credentialControls }
                        localSetup
                        Toggle("Enable usage tracking", isOn: Binding(get: { model.isEnabled(provider.id) },
                            set: { model.setEnabled($0, for: provider.id) }))
                            .toggleStyle(.switch).controlSize(.small)
                            .disabled(provider.requiresCredential && !model.savedCredentials.contains(provider.id) && !model.isEnabled(provider.id))
                        connectionStatus
                    } else {
                        Button("Add \(provider.title)") { model.addProvider(provider.id) }
                            .buttonStyle(.borderedProminent)
                        Text("Added providers appear in your menu bar panel. You can disconnect or remove them at any time.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            Divider()
            if model.isAdded(provider.id) {
                HStack {
                    Button("Remove Provider", role: .destructive) {
                        credential = ""
                        model.removeProvider(provider.id)
                    }
                    .help(provider.requiresCredential ? "Remove this provider and its saved Keychain credential" : "Remove this provider from Limitbar")
                    Spacer()
                    Button("Refresh Now") { model.refresh(provider.id) }
                        .disabled(!model.isEnabled(provider.id) || model.states[provider.id]?.isLoading == true)
                }
            }
            Text("Refreshes every 5 minutes and after wake. API keys and tokens entered here are stored in macOS Keychain.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var credentialControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(provider.credentialLabel).font(.system(size: 12, weight: .semibold))
            SecureField(model.savedCredentials.contains(provider.id) ? "Enter a replacement credential" : provider.credentialLabel,
                        text: $credential)
                .textFieldStyle(.roundedBorder).privacySensitive()
                .onSubmit(saveCredential)
            HStack {
                Button("Save & Connect", action: saveCredential).disabled(credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if model.savedCredentials.contains(provider.id) {
                    Label("Saved in Keychain", systemImage: "checkmark.shield").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }.padding(14).background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.035)))
    }

    @ViewBuilder private var localSetup: some View {
        if provider.id == .codex {
            HStack {
                Text(model.codexHome.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose Folder…", action: chooseCodexHome)
            }
        } else if provider.id == .antigravity {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("brew install --cask antigravity-cli").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install --cask antigravity-cli", forType: .string)
                    }
                }
                HStack {
                    Text(model.antigravityExecutable?.path ?? ProviderService.discoverAntigravity()?.path ?? "agy not found")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose CLI…", action: chooseAntigravity)
                    if model.antigravityExecutable != nil { Button("Auto") { model.setAntigravityExecutable(nil) } }
                }
            }
        }
    }

    @ViewBuilder private var connectionStatus: some View {
        switch model.states[provider.id] ?? .disconnected {
        case .loaded(let usage):
            Label("Connected · \(usage.subtitle)", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12)).foregroundStyle(.green)
        case .loading:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Reading quota…").font(.system(size: 12)) }
        case .failed(let message):
            Text(message).font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        case .disconnected:
            Text("Tracking is off").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func saveCredential() {
        if model.saveCredential(credential, provider: provider.id) { credential = "" }
    }

    private func chooseCodexHome() {
        let panel = NSOpenPanel()
        panel.title = "Choose your Codex folder"
        panel.message = "Select the .codex folder used by your signed-in Codex app or CLI."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = model.codexHome
        if panel.runModal() == .OK, let url = panel.url { model.setCodexHome(url) }
    }

    private func chooseAntigravity() {
        let panel = NSOpenPanel()
        panel.title = "Choose the Antigravity CLI"
        panel.message = "Select the agy executable (version 1.1.11 or later)."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            guard FileManager.default.isExecutableFile(atPath: url.path) else { model.alertMessage = "Choose an executable agy file."; return }
            model.setAntigravityExecutable(url)
        }
    }
}
