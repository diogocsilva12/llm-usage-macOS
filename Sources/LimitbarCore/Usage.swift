import Foundation

public enum ProviderID: String, CaseIterable, Identifiable, Sendable {
    case codex, antigravity, claude, copilot, zai, synthetic
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .codex: return "Codex"
        case .antigravity: return "Antigravity / Argon"
        case .claude: return "Claude"
        case .copilot: return "GitHub Copilot"
        case .zai: return "Z.ai / GLM"
        case .synthetic: return "Synthetic"
        }
    }
}

public struct UsageWindow: Equatable, Sendable {
    public let usedPercent: Double
    public let resetsAt: Date?
    public let duration: TimeInterval?

    public init(usedPercent: Double, resetsAt: Date? = nil, duration: TimeInterval? = nil) throws {
        guard usedPercent.isFinite, (0...100).contains(usedPercent) else { throw UsageError.invalidResponse }
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.duration = duration
    }
    public var fraction: Double { usedPercent / 100 }
    public var percentage: String { "\(Int(usedPercent.rounded()))%" }
}

public enum QuotaFamily: Equatable, Sendable {
    case gemini, claudeAndGPT
}

public struct QuotaGroup: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let primary: UsageWindow?
    public let secondary: UsageWindow?
    public let primaryTitle: String
    public let secondaryTitle: String
    public let family: QuotaFamily?

    public var fiveHour: UsageWindow? { primaryTitle == "5 hours" ? primary : nil }
    public var weekly: UsageWindow? { secondaryTitle == "Week" ? secondary : primaryTitle == "Week" ? primary : nil }

    public init(id: String, name: String, fiveHour: UsageWindow?, weekly: UsageWindow?, family: QuotaFamily? = nil) {
        self.init(id: id, name: name, primary: fiveHour, primaryTitle: "5 hours", secondary: weekly,
                  secondaryTitle: "Week", family: family)
    }

    public init(id: String, name: String, primary: UsageWindow?, primaryTitle: String,
                secondary: UsageWindow? = nil, secondaryTitle: String = "", family: QuotaFamily? = nil) {
        self.id = id
        self.name = name
        self.primary = primary
        self.secondary = secondary
        self.primaryTitle = primaryTitle
        self.secondaryTitle = secondaryTitle
        self.family = family
    }
}

public struct ProviderUsage: Equatable, Identifiable, Sendable {
    public let id: ProviderID
    public let subtitle: String
    public let updatedAt: Date
    public let groups: [QuotaGroup]
    public let resetCredits: ResetCredits?
    public let notes: [String]

    public init(id: ProviderID, subtitle: String, updatedAt: Date, groups: [QuotaGroup], resetCredits: ResetCredits? = nil,
                notes: [String] = []) {
        self.id = id
        self.subtitle = subtitle
        self.updatedAt = updatedAt
        self.groups = groups
        self.resetCredits = resetCredits
        self.notes = notes
    }
    public func withResetCredits(_ credits: ResetCredits) -> ProviderUsage {
        ProviderUsage(id: id, subtitle: subtitle, updatedAt: updatedAt, groups: groups, resetCredits: credits, notes: notes)
    }
    public var summary: UsageWindow? {
        let groups = id == .antigravity ? geminiGroups : self.groups
        if id == .antigravity,
           let argon = groups.first(where: { $0.name.localizedCaseInsensitiveContains("argon") }) {
            return argon.weekly ?? argon.fiveHour
        }
        return groups.first?.primary ?? groups.first?.secondary
    }
    public var geminiGroups: [QuotaGroup] { groups.filter { $0.family != .claudeAndGPT } }
    public var claudeAndGPTGroups: [QuotaGroup] { groups.filter { $0.family == .claudeAndGPT } }
    public func isStale(at now: Date = Date()) -> Bool { now.timeIntervalSince(updatedAt) > 15 * 60 }
}

public enum UsageError: LocalizedError, Equatable, Sendable {
    case notSignedIn, expiredSession, accessDenied, rateLimited, network
    case invalidResponse, noQuota, cliMissing, cliOutdated, commandFailed, timedOut, outputTooLarge
    case keychainDenied
    case claudeNotSignedIn, missingProviderCredential, providerSessionExpired, keychainWriteFailed

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to Codex with your ChatGPT account, then refresh."
        case .expiredSession: return "Your Codex session expired. Open Codex and sign in again."
        case .accessDenied: return "This account cannot access its usage limits. Check your subscription."
        case .rateLimited: return "Too many requests. Automatic refresh will try again later."
        case .network: return "Couldn't reach the usage service. Check your connection and refresh."
        case .invalidResponse: return "The usage response wasn't recognized. Update the provider app and try again."
        case .noQuota: return "No measured quota was returned for this account."
        case .cliMissing: return "Install the Antigravity CLI, run agy to sign in, then refresh."
        case .cliOutdated: return "Update the Antigravity CLI to version 1.1.11 or later."
        case .commandFailed: return "Antigravity couldn't report usage. Run agy, check your sign-in, then refresh."
        case .timedOut: return "Antigravity took too long to respond. Open agy and try again."
        case .outputTooLarge: return "The usage report was unexpectedly large. Update Antigravity and retry."
        case .keychainDenied: return "Allow Limitbar to read the provider sign-in in Keychain, then refresh."
        case .claudeNotSignedIn: return "Open Claude Code, sign in with your Claude subscription, then refresh."
        case .missingProviderCredential: return "Add a token or API key in Connections to read this provider's quota."
        case .providerSessionExpired: return "This provider rejected the sign-in. Reconnect it in Connections and refresh."
        case .keychainWriteFailed: return "Couldn't save this credential in macOS Keychain. Check Keychain access and retry."
        }
    }
}

enum UsageDate {
    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
