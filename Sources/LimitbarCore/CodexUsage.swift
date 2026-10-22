import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only the access token is read. Limitbar never rotates or writes CLI credentials.
public struct CodexCredentials: Sendable {
    let accessToken: String
    let accountID: String?

    public static func decode(_ data: Data) throws -> Self {
        struct Auth: Decodable {
            struct Tokens: Decodable { let access_token: String; let account_id: String? }
            let tokens: Tokens?
        }
        guard data.count <= 1_048_576,
              let auth = try? JSONDecoder().decode(Auth.self, from: data),
              let tokens = auth.tokens,
              !tokens.access_token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !tokens.access_token.contains(where: { $0.isNewline }) else { throw UsageError.notSignedIn }
        if let account = tokens.account_id, account.contains(where: { $0.isNewline }) {
            throw UsageError.notSignedIn
        }
        return Self(accessToken: tokens.access_token, accountID: tokens.account_id)
    }
}

public enum CodexUsage {
    public static func request(credentials: CodexCredentials) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let account = credentials.accountID, !account.isEmpty {
            request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Limitbar/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    public static func parse(_ data: Data, now: Date = Date()) throws -> ProviderUsage {
        guard data.count <= 1_048_576 else { throw UsageError.outputTooLarge }
        let payload: Response
        do { payload = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw UsageError.invalidResponse }
        var groups: [QuotaGroup] = []
        if let limits = payload.rate_limit {
            if let group = try group(limits, id: "codex", name: "Codex") { groups.append(group) }
        }
        for (index, extra) in (payload.additional_rate_limits ?? []).enumerated() {
            if let group = try group(extra.rate_limit, id: "additional-\(index)", name: extra.limit_name ?? "Additional limit") {
                groups.append(group)
            }
        }
        guard !groups.isEmpty else { throw UsageError.noQuota }
        let plan = payload.plan_type.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
        return ProviderUsage(id: .codex, subtitle: plan.map { "ChatGPT · \($0)" } ?? "ChatGPT account",
                             updatedAt: now, groups: groups)
    }

    private static func group(_ limits: Limits, id: String, name: String) throws -> QuotaGroup? {
        var fiveHour: UsageWindow?
        var weekly: UsageWindow?
        for value in [limits.primary_window, limits.secondary_window].compactMap({ $0 }) {
            guard let percent = value.used_percent else { continue }
            let window = try UsageWindow(usedPercent: percent,
                resetsAt: value.reset_at.map { Date(timeIntervalSince1970: $0) },
                duration: value.limit_window_seconds)
            // Classify by actual duration, never by primary/secondary ordering.
            switch value.limit_window_seconds {
            case 18_000: fiveHour = window
            case 604_800: weekly = window
            default: continue
            }
        }
        guard fiveHour != nil || weekly != nil else { return nil }
        return QuotaGroup(id: id, name: name, fiveHour: fiveHour, weekly: weekly)
    }

    private struct Response: Decodable {
        let plan_type: String?
        let rate_limit: Limits?
        let additional_rate_limits: [Additional]?
    }
    private struct Additional: Decodable { let limit_name: String?; let rate_limit: Limits }
    private struct Limits: Decodable { let primary_window: Window?; let secondary_window: Window? }
    private struct Window: Decodable {
        let used_percent: Double?
        let limit_window_seconds: Double?
        let reset_at: Double?
    }
}
