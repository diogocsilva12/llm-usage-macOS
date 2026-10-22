import Foundation

public struct ProviderDefinition: Identifiable, Sendable {
    public enum Authentication: Sendable { case localSignIn, accessToken, apiKey }
    public let id: ProviderID
    public let summary: String
    public let authentication: Authentication
    public let instructions: String
    public let website: URL
    public var title: String { id.title }
    public var requiresCredential: Bool { authentication != .localSignIn }
    public var credentialLabel: String { authentication == .accessToken ? "GitHub access token" : "API key" }
    public var authenticationLabel: String {
        switch authentication {
        case .localSignIn: return "Existing sign-in"
        case .accessToken: return "GitHub token"
        case .apiKey: return "API key"
        }
    }
}

public enum ProviderCatalog {
    public static let providers: [ProviderDefinition] = [
        ProviderDefinition(id: .codex, summary: "ChatGPT coding limits and reset credits", authentication: .localSignIn,
            instructions: "Sign in to the Codex app or run codex login with your ChatGPT account. Limitbar reads the existing session.",
            website: URL(string: "https://developers.openai.com/codex/")!),
        ProviderDefinition(id: .antigravity, summary: "Argon, Gemini, and Claude/GPT quotas", authentication: .localSignIn,
            instructions: "Install the Antigravity CLI, then run agy once to sign in. Limitbar reads its usage report; the desktop app can stay closed.",
            website: URL(string: "https://antigravity.google/")!),
        ProviderDefinition(id: .claude, summary: "Claude subscription and model limits", authentication: .localSignIn,
            instructions: "Sign in to Claude Code with your Claude Pro or Max subscription. Allow Limitbar to read the Claude Code sign-in in Keychain when macOS asks. Anthropic API keys do not expose subscription quotas.",
            website: URL(string: "https://claude.com/product/claude-code")!),
        ProviderDefinition(id: .copilot, summary: "Monthly premium requests and chat allowance", authentication: .accessToken,
            instructions: "Use a GitHub account token with access to your Copilot quota. To copy the OAuth token from your GitHub CLI sign-in, run gh auth token | pbcopy, then paste it here. Fine-grained repository tokens may not expose Copilot usage.",
            website: URL(string: "https://github.com/settings/copilot")!),
        ProviderDefinition(id: .zai, summary: "GLM Coding Plan and MCP allowance", authentication: .apiKey,
            instructions: "Add a Z.ai global Coding Plan API key. This integration connects to api.z.ai for personal quota; BigModel China and team plans use different endpoints.",
            website: URL(string: "https://z.ai/manage-apikey/coding-plan/personal/my-plan")!),
        ProviderDefinition(id: .synthetic, summary: "Five-hour, weekly, and search quotas", authentication: .apiKey,
            instructions: "Add your Synthetic API key. Limitbar reads the subscription's rolling five-hour limit, weekly tokens, and hourly search allowance when reported.",
            website: URL(string: "https://dev.synthetic.new/docs/api/getting-started")!),
    ]

    public static func definition(for id: ProviderID) -> ProviderDefinition {
        providers.first { $0.id == id }!
    }

    /// Preserve providers already connected by versions preceding the catalog.
    public static func restoredProviders(saved: [String]?, previouslyEnabled: [ProviderID]) -> [ProviderID] {
        let candidates = saved.map { $0.compactMap(ProviderID.init(rawValue:)) } ?? previouslyEnabled
        var seen = Set<ProviderID>()
        return candidates.filter { seen.insert($0).inserted }
    }
}
