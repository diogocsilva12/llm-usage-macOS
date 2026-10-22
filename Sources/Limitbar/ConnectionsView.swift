import AppKit
import SwiftUI
import LimitbarCore

@MainActor
struct ConnectionsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your accounts. One glance.").font(.system(size: 21, weight: .semibold))
                Text("Connect the sign-ins already on this Mac.")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                providerToggle(.codex)
                Text("Sign in to the Codex app or run codex login with your ChatGPT account. Limitbar reads your existing session to fetch usage.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(model.codexHome.path).font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose Folder…") { chooseCodexHome() }
                }
                Link("Get Codex ↗", destination: URL(string: "https://developers.openai.com/codex/")!).font(.system(size: 12))
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                providerToggle(.antigravity)
                Text("Install the Antigravity CLI, then run agy once to sign in. Limitbar reads its usage report, including separate Argon quotas. The desktop app does not need to stay open.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("brew install --cask antigravity-cli")
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install --cask antigravity-cli", forType: .string)
                    }
                }
                HStack {
                    Text(model.antigravityExecutable?.path ?? ProviderService.discoverAntigravity()?.path ?? "agy not found")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose CLI…") { chooseAntigravity() }
                    if model.antigravityExecutable != nil {
                        Button("Auto") { model.setAntigravityExecutable(nil) }
                    }
                }
                Link("Get Antigravity ↗", destination: URL(string: "https://antigravity.google/")!).font(.system(size: 12))
            }
            Divider()
            Text("Refreshes every 5 minutes and when your Mac wakes. Missing limits stay blank. No analytics, credential copies, or model prompts.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Limitbar 1.0").font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
                Button("Refresh Now") { model.refresh() }.disabled(model.isRefreshing)
            }
        }
        .padding(26).frame(width: 480)
        .alert("Limitbar", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK") { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
    }

    private func providerToggle(_ id: ProviderID) -> some View {
        Toggle(isOn: Binding(get: { model.isEnabled(id) }, set: { model.setEnabled($0, for: id) })) {
            HStack(spacing: 8) {
                ProviderMark(id: id).frame(width: 18, height: 18)
                Text(id == .antigravity ? "Antigravity / Argon" : "Codex").font(.system(size: 14, weight: .semibold))
            }
        }.toggleStyle(.switch).controlSize(.small)
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
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                model.alertMessage = "Choose an executable agy file."
                return
            }
            model.setAntigravityExecutable(url)
        }
    }
}
