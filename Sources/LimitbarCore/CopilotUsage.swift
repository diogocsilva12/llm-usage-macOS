import Foundation

public enum CopilotUsage {
    public static func parse(_ data: Data, now: Date = Date()) throws -> ProviderUsage {
        let root = try QuotaPayload.object(data)
        let quotas = root["quota_snapshots"] as? [String: Any] ?? [:]
        let reset = QuotaPayload.date(root["quota_reset_date"])
        var notes: [String] = []
        func window(_ key: String, name: String) throws -> UsageWindow? {
            guard let quota = quotas[key] as? [String: Any] else { return nil }
            if quota["unlimited"] as? Bool == true { notes.append("\(name): unlimited"); return nil }
            let limit = try QuotaPayload.number(quota["entitlement"])
            let remaining = try QuotaPayload.number(quota["remaining"])
            if let limit, limit < 0 { throw UsageError.invalidResponse }
            if let remaining, remaining < 0 { throw UsageError.invalidResponse }
            // Zero-entitlement seats can be billed per token and carry placeholder percentages.
            if limit == 0 { return nil }
            let used: Double
            if let percent = try QuotaPayload.number(quota["percent_remaining"]) {
                guard (0...100).contains(percent) else { throw UsageError.invalidResponse }
                used = 100 - percent
            } else if let limit, limit > 0, let remaining {
                used = (limit - remaining) / limit * 100
            } else { return nil }
            return try UsageWindow(usedPercent: used, resetsAt: reset)
        }
        let premium = try window("premium_interactions", name: "Premium requests")
        let chat = try window("chat", name: "Chat")
        let completions = try window("completions", name: "Completions")
        var groups: [QuotaGroup] = []
        if premium != nil || chat != nil {
            groups.append(QuotaGroup(id: "copilot", name: "Monthly requests", primary: premium,
                                     primaryTitle: "Premium / month", secondary: chat, secondaryTitle: "Chat / month"))
        }
        if let completions {
            groups.append(QuotaGroup(id: "completions", name: "Completions", primary: completions, primaryTitle: "Monthly"))
        }
        if root["token_based_billing"] as? Bool == true { notes.append("Token-based billing; no included allowance inferred") }
        guard !groups.isEmpty || !notes.isEmpty else { throw UsageError.noQuota }
        let plan = (root["copilot_plan"] as? String)?.replacingOccurrences(of: "_", with: " ").capitalized
        return ProviderUsage(id: .copilot, subtitle: plan.map { "Copilot · \($0)" } ?? "GitHub Copilot account",
                             updatedAt: now, groups: groups, notes: notes)
    }
}
