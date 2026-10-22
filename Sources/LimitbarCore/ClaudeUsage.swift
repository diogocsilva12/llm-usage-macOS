import Foundation

public struct ClaudeCredentials: Sendable {
    let accessToken: String
    let plan: String?

    public static func decode(_ data: Data) throws -> ClaudeCredentials {
        guard let root = try? QuotaPayload.object(data),
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty, !token.contains(where: { $0.isWhitespace }) else { throw UsageError.claudeNotSignedIn }
        return ClaudeCredentials(accessToken: token, plan: oauth["subscriptionType"] as? String)
    }
}

public enum ClaudeUsage {
    public static func parse(_ data: Data, plan: String? = nil, now: Date = Date()) throws -> ProviderUsage {
        let root = try QuotaPayload.object(data)
        func window(_ key: String, duration: TimeInterval) throws -> UsageWindow? {
            guard let value = root[key] as? [String: Any], let used = try QuotaPayload.number(value["utilization"]) else { return nil }
            return try UsageWindow(usedPercent: used, resetsAt: QuotaPayload.date(value["resets_at"]), duration: duration)
        }
        var groups: [QuotaGroup] = []
        let session = try window("five_hour", duration: 18_000)
        let week = try window("seven_day", duration: 604_800)
        if session != nil || week != nil {
            groups.append(QuotaGroup(id: "claude", name: "Claude subscription", fiveHour: session, weekly: week))
        }
        for (key, name) in [("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet"), ("seven_day_oauth_apps", "OAuth apps")] {
            if let quota = try window(key, duration: 604_800) {
                groups.append(QuotaGroup(id: key, name: name, fiveHour: nil, weekly: quota))
            }
        }
        guard !groups.isEmpty else { throw UsageError.noQuota }
        return ProviderUsage(id: .claude, subtitle: plan.map { "Claude · \($0.capitalized)" } ?? "Claude subscription",
                             updatedAt: now, groups: groups)
    }
}
