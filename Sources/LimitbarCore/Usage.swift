import Foundation

public enum ProviderID: String, CaseIterable, Identifiable, Sendable {
    case codex, antigravity
    public var id: String { rawValue }
    public var title: String { self == .codex ? "Codex" : "Antigravity" }
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
    public let fiveHour: UsageWindow?
    public let weekly: UsageWindow?
    public let family: QuotaFamily?

    public init(id: String, name: String, fiveHour: UsageWindow?, weekly: UsageWindow?, family: QuotaFamily? = nil) {
        self.id = id
        self.name = name
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.family = family
    }
}

public struct ProviderUsage: Equatable, Identifiable, Sendable {
    public let id: ProviderID
    public let subtitle: String
    public let updatedAt: Date
    public let groups: [QuotaGroup]

    public init(id: ProviderID, subtitle: String, updatedAt: Date, groups: [QuotaGroup]) {
        self.id = id
        self.subtitle = subtitle
        self.updatedAt = updatedAt
        self.groups = groups
    }
    public var summary: UsageWindow? {
        let groups = id == .antigravity ? geminiGroups : self.groups
        if id == .antigravity,
           let argon = groups.first(where: { $0.name.localizedCaseInsensitiveContains("argon") }) {
            return argon.weekly ?? argon.fiveHour
        }
        return groups.first?.fiveHour ?? groups.first?.weekly
    }
    public var geminiGroups: [QuotaGroup] { groups.filter { $0.family != .claudeAndGPT } }
    public var claudeAndGPTGroups: [QuotaGroup] { groups.filter { $0.family == .claudeAndGPT } }
    public func isStale(at now: Date = Date()) -> Bool { now.timeIntervalSince(updatedAt) > 15 * 60 }
}

public enum UsageError: LocalizedError, Equatable, Sendable {
    case notSignedIn, expiredSession, accessDenied, rateLimited, network
    case invalidResponse, noQuota, cliMissing, cliOutdated, commandFailed, timedOut, outputTooLarge
    case keychainDenied

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to Codex with your ChatGPT account, then refresh."
        case .expiredSession: return "Your Codex session expired. Open Codex and sign in again."
        case .accessDenied: return "This account cannot access its usage limits. Check your subscription."
        case .rateLimited: return "Too many requests. Automatic refresh will try again later."
        case .network: return "Couldn't reach the usage service. Check your connection and refresh."
        case .invalidResponse: return "The usage response wasn't recognized. Update the provider app and try again."
        case .noQuota: return "No measured 5-hour or weekly limits were returned for this account."
        case .cliMissing: return "Install the Antigravity CLI, run agy to sign in, then refresh."
        case .cliOutdated: return "Update the Antigravity CLI to version 1.1.11 or later."
        case .commandFailed: return "Antigravity couldn't report usage. Run agy, check your sign-in, then refresh."
        case .timedOut: return "Antigravity took too long to respond. Open agy and try again."
        case .outputTooLarge: return "The usage report was unexpectedly large. Update Antigravity and retry."
        case .keychainDenied: return "Allow Limitbar to read your Codex sign-in in Keychain, then refresh."
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
