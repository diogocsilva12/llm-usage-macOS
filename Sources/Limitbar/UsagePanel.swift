import AppKit
import SwiftUI
import LimitbarCore

enum PanelStyle {
    static let width: CGFloat = 420
    static let labelWidth: CGFloat = 152
    static let metricWidth: CGFloat = 104
    static let secondary = Color(red: 0.65, green: 0.70, blue: 0.83)
    static let muted = Color(red: 0.48, green: 0.55, blue: 0.72)
    static let line = Color.white.opacity(0.10)
}

@MainActor
struct UsagePanel: View {
    @ObservedObject var model: AppModel
    let openConnections: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack {
                    Text("Limits").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button { model.isPinned.toggle() } label: {
                        Image(systemName: model.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11))
                            .foregroundStyle(model.isPinned ? Color.white : PanelStyle.muted)
                    }
                    .buttonStyle(.plain)
                    .help(model.isPinned ? "Unpin panel" : "Keep panel open")
                    .accessibilityLabel(model.isPinned ? "Unpin panel" : "Pin panel")
                }.frame(width: PanelStyle.labelWidth)
                Text("5 hours").frame(width: PanelStyle.metricWidth, alignment: .leading)
                Text("Week").frame(width: PanelStyle.metricWidth, alignment: .leading)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(PanelStyle.secondary)
            .padding(.top, 15)
            .padding(.bottom, 13)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(ProviderID.allCases) { id in
                        provider(id)
                        if id != ProviderID.allCases.last {
                            Rectangle().fill(PanelStyle.line).frame(height: 1).padding(.vertical, 14)
                        }
                    }
                }
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)
            .frame(height: contentHeight)

            Rectangle().fill(PanelStyle.line).frame(height: 1)
            VStack(spacing: 2) {
                footerButton("Refresh Now", icon: "arrow.clockwise", shortcut: "⌘R") { model.refresh() }
                    .disabled(model.isRefreshing)
                    .help("Refresh now. Connected providers also refresh every five minutes.")
                    .keyboardShortcut("r", modifiers: .command)
                HStack(spacing: 10) {
                    Image(systemName: "desktopcomputer").frame(width: 16)
                    Text("Open at Login")
                    Spacer()
                    Toggle("Open at Login", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }.padding(.horizontal, 3).frame(height: 29)
                footerButton("Connections…", icon: "slider.horizontal.3", shortcut: "⌘,") { openConnections() }
                    .keyboardShortcut(",", modifiers: .command)
                footerButton("Quit Limitbar", icon: "power", shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .font(.system(size: 13))
            .foregroundStyle(PanelStyle.secondary)
            .padding(.top, 7)
            .padding(.bottom, 9)
        }
        .padding(.horizontal, 18)
        .frame(width: PanelStyle.width)
        .foregroundStyle(Color(red: 0.89, green: 0.92, blue: 0.99))
        .background {
            ZStack {
                VisualEffect()
                LinearGradient(colors: [Color(red: 0.075, green: 0.10, blue: 0.23).opacity(0.94),
                                        Color(red: 0.10, green: 0.18, blue: 0.38).opacity(0.93),
                                        Color(red: 0.19, green: 0.20, blue: 0.34).opacity(0.94)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .preferredColorScheme(.dark)
        .alert("Limitbar", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK") { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
    }

    private var contentHeight: CGFloat {
        let height = ProviderID.allCases.reduce(CGFloat(0)) { total, id in
            if let usage = model.states[id]?.usage {
                let sections = id == .antigravity
                    ? (usage.geminiGroups.isEmpty ? 0 : 1) + (usage.claudeAndGPTGroups.isEmpty ? 0 : 1)
                    : 1
                return total + CGFloat(sections) * 63
                    + CGFloat(max(0, usage.groups.count - sections)) * 56
                    + CGFloat(max(0, sections - 1)) * 29
            }
            if case .failed? = model.states[id] { return total + 106 }
            return total + 65
        } + 43
        return min(height, max(200, (NSScreen.main?.visibleFrame.height ?? 800) - 230))
    }

    @ViewBuilder
    private func provider(_ id: ProviderID) -> some View {
        switch model.states[id] ?? .disconnected {
        case .loaded(let usage):
            if id == .antigravity {
                let gemini = orderedGeminiGroups(usage.geminiGroups)
                VStack(spacing: 0) {
                    if let first = gemini.first {
                        let hasArgon = first.name.localizedCaseInsensitiveContains("argon")
                        usageSection(usage, groups: gemini, title: hasArgon ? "Argon" : "Antigravity",
                                     subtitle: hasArgon ? "Google Antigravity" : first.name, logo: .antigravity)
                    }
                    if !usage.claudeAndGPTGroups.isEmpty {
                        if !gemini.isEmpty {
                            Rectangle().fill(PanelStyle.line).frame(height: 1).padding(.vertical, 14)
                        }
                        usageSection(usage, groups: usage.claudeAndGPTGroups, title: "Claude & GPT",
                                     subtitle: "Google Antigravity", logo: .claude)
                    }
                }
            } else {
                usageSection(usage, groups: usage.groups, title: id.title, subtitle: usage.subtitle, logo: .codex)
            }
        case .disconnected:
            connectionState(id, message: id == .codex ? "Use your ChatGPT sign-in" : "Argon, Gemini & shared limits") {
                Button("Connect") { model.setEnabled(true, for: id) }.buttonStyle(ConnectionButtonStyle())
            }
        case .loading:
            connectionState(id, message: "Reading your usage…") {
                ProgressView().controlSize(.small).frame(width: 70)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                connectionState(id, message: "Usage unavailable") {
                    Button("Retry") { model.refresh(id) }.buttonStyle(ConnectionButtonStyle())
                }
                Text(message).font(.system(size: 11)).foregroundStyle(PanelStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 27)
            }
        }
    }

    private func usageSection(_ usage: ProviderUsage, groups: [QuotaGroup], title: String,
                              subtitle: String, logo: ProviderLogo) -> some View {
        VStack(spacing: 11) {
            if let first = groups.first {
                HStack(alignment: .top, spacing: 12) {
                    HStack(alignment: .top, spacing: 8) {
                        ProviderMark(logo: logo).frame(width: 19, height: 21)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.system(size: 14, weight: .semibold))
                            Text(subtitle).font(.system(size: 11)).foregroundStyle(PanelStyle.secondary)
                                .lineLimit(1).help(subtitle)
                            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                                Text(updatedLabel(usage.updatedAt, now: timeline.date))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(usage.isStale(at: timeline.date) ? Color.orange : PanelStyle.muted)
                            }
                        }
                    }.frame(width: PanelStyle.labelWidth, alignment: .leading)
                    MetricCell(window: first.fiveHour, weekly: false)
                    MetricCell(window: first.weekly, weekly: true)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(title), \(first.name), \(subtitle)")
            }
            ForEach(Array(groups.dropFirst())) { group in
                HStack(alignment: .top, spacing: 12) {
                    Text(group.name).font(.system(size: 11.5)).foregroundStyle(PanelStyle.secondary)
                        .lineLimit(2).padding(.leading, 27)
                        .frame(width: PanelStyle.labelWidth, alignment: .leading).help(group.name)
                    MetricCell(window: group.fiveHour, weekly: false, compact: true)
                    MetricCell(window: group.weekly, weekly: true, compact: true)
                }
            }
        }
    }

    private func connectionState<Content: View>(_ id: ProviderID, message: String, @ViewBuilder action: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            ProviderMark(id: id).frame(width: 19, height: 21)
            VStack(alignment: .leading, spacing: 4) {
                Text(id.title).font(.system(size: 14, weight: .semibold))
                Text(message).font(.system(size: 11)).foregroundStyle(PanelStyle.secondary)
            }
            Spacer()
            action()
        }.frame(minHeight: 59)
    }

    private func footerButton(_ title: String, icon: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 16)
                Text(title)
                Spacer()
                Text(shortcut).font(.system(size: 11)).foregroundStyle(PanelStyle.muted)
            }.padding(.horizontal, 3).frame(height: 29).contentShape(Rectangle())
        }.buttonStyle(MenuRowStyle())
    }

    private func orderedGeminiGroups(_ groups: [QuotaGroup]) -> [QuotaGroup] {
        let argon = groups.filter { $0.name.localizedCaseInsensitiveContains("argon") }
        return argon + groups.filter { !$0.name.localizedCaseInsensitiveContains("argon") }
    }

    private func updatedLabel(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        return minutes == 0 ? "updated just now" : "updated \(minutes) min ago"
    }
}

struct MetricCell: View {
    let window: UsageWindow?
    let weekly: Bool
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let window {
                HStack(spacing: 3) {
                    Text(window.percentage).monospacedDigit()
                    if !compact { Text("used").foregroundStyle(PanelStyle.secondary) }
                }.font(.system(size: compact ? 11.5 : 13))
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.13))
                        if window.fraction > 0 {
                            Capsule().fill(window.usedPercent >= 90 ? Color(red: 0.97, green: 0.45, blue: 0.40)
                                           : window.usedPercent >= 75 ? Color(red: 1, green: 0.68, blue: 0.08)
                                           : Color(red: 0.81, green: 0.86, blue: 0.98))
                                .frame(width: max(3, geometry.size.width * window.fraction))
                        }
                    }
                }.frame(height: 4)
                Text(resetLabel(window.resetsAt))
                    .font(.system(size: 10.5)).foregroundStyle(PanelStyle.muted)
                    .lineLimit(1).minimumScaleFactor(0.85)
            } else {
                Text("—").font(.system(size: 13)).foregroundStyle(PanelStyle.muted)
                Text("not reported").font(.system(size: 10)).foregroundStyle(PanelStyle.muted)
            }
        }
        .frame(width: PanelStyle.metricWidth, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weekly ? "Weekly usage" : "Five-hour usage")
        .accessibilityValue(window.map { "\($0.percentage) used, \(resetLabel($0.resetsAt))" } ?? "Not reported")
    }

    private func resetLabel(_ date: Date?) -> String {
        guard let date else { return "reset not reported" }
        if date < Date() { return "awaiting reset" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(weekly || !Calendar.current.isDateInToday(date) ? "EEE HH:mm" : "HH:mm")
        return "resets \(formatter.string(from: date))"
    }
}

struct ProviderMark: View {
    let logo: ProviderLogo
    var monochrome = false

    var body: some View {
        Image(nsImage: ProviderArtwork.image(for: logo)).resizable().renderingMode(.template).scaledToFit()
            .foregroundStyle(monochrome ? Color.primary : tint)
            .accessibilityHidden(true)
    }

    private var tint: Color {
        switch logo {
        case .codex: return Color(red: 0.78, green: 0.85, blue: 0.99)
        case .antigravity: return Color(red: 0.58, green: 0.58, blue: 0.98)
        case .claude: return Color(red: 0.88, green: 0.53, blue: 0.38)
        }
    }
}

extension ProviderMark {
    init(id: ProviderID) { self.init(logo: ProviderLogo(id)) }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(configuration: configuration)
    }
    private struct HoverRow: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(configuration.isPressed ? 0.14 : hovering ? 0.07 : 0)))
                .onHover { hovering = $0 }
        }
    }
}

private struct ConnectionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(Color.white.opacity(configuration.isPressed ? 0.18 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.12)))
    }
}
