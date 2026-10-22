import AppKit
import LimitbarCore

enum ProviderLogo {
    case codex, antigravity, claude, copilot, zai, synthetic

    init(_ provider: ProviderID) {
        switch provider {
        case .codex: self = .codex
        case .antigravity: self = .antigravity
        case .claude: self = .claude
        case .copilot: self = .copilot
        case .zai: self = .zai
        case .synthetic: self = .synthetic
        }
    }
}

enum ProviderArtwork {
    static let codex = load("CodexLogo")
    static let claude = load("ClaudeLogo")
    static let copilot = load("CopilotLogo")
    static let zai = load("ZaiLogo")
    static let synthetic = load("SyntheticLogo")

    static func image(for logo: ProviderLogo) -> NSImage {
        switch logo {
        case .codex: return codex
        case .claude: return claude
        case .copilot: return copilot
        case .zai: return zai
        case .synthetic: return synthetic
        case .antigravity: return NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)!
        }
    }

    /// The whole menu image is a template, so icons and percentages follow the menu bar appearance.
    static func menuBarImage(summaries: [(ProviderID, String)]) -> NSImage {
        guard !summaries.isEmpty else {
            let image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Limitbar")!
            image.size = NSSize(width: 16, height: 16)
            image.isTemplate = true
            return image
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let widths = summaries.map { CGFloat(16) + ceil(($0.1 as NSString).size(withAttributes: attributes).width) }
        let width = widths.reduce(0, +) + CGFloat(max(0, summaries.count - 1)) * 9
        let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { _ in
            var x: CGFloat = 0
            for (index, summary) in summaries.enumerated() {
                Self.image(for: ProviderLogo(summary.0)).draw(in: NSRect(x: x, y: 3, width: 12, height: 12))
                let text = summary.1 as NSString
                let textHeight = text.size(withAttributes: attributes).height
                text.draw(at: NSPoint(x: x + 16, y: (18 - textHeight) / 2), withAttributes: attributes)
                x += widths[index] + 9
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func load(_ name: String) -> NSImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing bundled provider logo: \(name)")
        }
        image.isTemplate = true
        return image
    }
}
