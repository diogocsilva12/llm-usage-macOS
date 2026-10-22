import Foundation

public enum SyntheticUsage {
    public static func parse(_ data: Data, now: Date = Date()) throws -> ProviderUsage {
        let root = try QuotaPayload.object(data)
        let payload = root["data"] as? [String: Any] ?? root
        func window(_ value: Any?, duration: TimeInterval) throws -> UsageWindow? {
            guard let value = value as? [String: Any] else { return nil }
            var used = try QuotaPayload.firstNumber(value, keys: ["percentUsed", "usedPercent", "usagePercent", "used_percent"])
            if used == nil, let remaining = try QuotaPayload.firstNumber(value, keys: ["percentRemaining", "remainingPercent", "percent_remaining"]) {
                guard (0...100).contains(remaining) else { throw UsageError.invalidResponse }
                used = 100 - remaining
            }
            if used == nil {
                let limit = try QuotaPayload.firstNumber(value, keys: ["limit", "messageLimit", "maxRequests", "requestLimit", "capacity"])
                let consumed = try QuotaPayload.firstNumber(value, keys: ["used", "usage", "requests", "requestCount", "consumed"])
                let remaining = try QuotaPayload.firstNumber(value, keys: ["remaining", "left", "available"])
                if let limit, limit > 0 {
                    if let consumed { used = consumed / limit * 100 }
                    else if let remaining { used = (limit - remaining) / limit * 100 }
                }
            }
            guard let used else { return nil }
            let resetsAt = ["resetsAt", "resetAt", "reset_at", "renewsAt", "nextRegenAt", "nextTickAt", "periodEnd"]
                .compactMap { QuotaPayload.date(value[$0]) }.first
            return try UsageWindow(usedPercent: used, resetsAt: resetsAt, duration: duration)
        }
        let fiveHour = try window(payload["rollingFiveHourLimit"], duration: 18_000)
        let weekly = try window(payload["weeklyTokenLimit"], duration: 604_800)
        let search = try window((payload["search"] as? [String: Any])?["hourly"], duration: 3_600)
        var groups: [QuotaGroup] = []
        if fiveHour != nil || weekly != nil { groups.append(QuotaGroup(id: "synthetic", name: "Subscription", fiveHour: fiveHour, weekly: weekly)) }
        if let search { groups.append(QuotaGroup(id: "search", name: "Search", primary: search, primaryTitle: "Hourly")) }
        guard !groups.isEmpty else { throw UsageError.noQuota }
        return ProviderUsage(id: .synthetic, subtitle: (payload["plan"] as? String) ?? "Synthetic subscription", updatedAt: now, groups: groups)
    }
}
