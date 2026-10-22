import Foundation

public enum ZaiUsage {
    public static func parse(_ data: Data, now: Date = Date()) throws -> ProviderUsage {
        let root = try QuotaPayload.object(data)
        let code = try QuotaPayload.number(root["code"])
        if code == 401 { throw UsageError.providerSessionExpired }
        if code == 403 { throw UsageError.accessDenied }
        guard root["success"] as? Bool == true, code == 200,
              let payload = root["data"] as? [String: Any], let limits = payload["limits"] as? [[String: Any]] else {
            throw UsageError.invalidResponse
        }
        var groups: [QuotaGroup] = []
        for (index, value) in limits.enumerated() {
            guard let type = value["type"] as? String, ["TOKENS_LIMIT", "CREDIT_LIMIT", "TIME_LIMIT"].contains(type) else { continue }
            let total = try QuotaPayload.number(value["usage"])
            let current = try QuotaPayload.number(value["currentValue"])
            let remaining = try QuotaPayload.number(value["remaining"])
            if total == 0 { continue }
            var percent = try QuotaPayload.number(value["percentage"])
            if let total, total > 0 {
                if let remaining { percent = max(total - remaining, current ?? total - remaining) / total * 100 }
                else if let current { percent = current / total * 100 }
            }
            guard let percent else { continue }
            let unit = try QuotaPayload.number(value["unit"])
            let count = try QuotaPayload.number(value["number"])
            if let count, count < 0 || count > 1_000_000 || count.rounded(.towardZero) != count {
                throw UsageError.invalidResponse
            }
            let isMonthlyMCP = type == "TIME_LIMIT" && unit == 5 && count == 1
            var duration: Double?
            var label = "Quota"
            if isMonthlyMCP { label = "Monthly" }
            else if let count, count > 0 {
                switch unit {
                case 1: duration = count * 86_400; label = count == 1 ? "Daily" : "\(Int(count)) days"
                case 3: duration = count * 3_600; label = count == 5 ? "5 hours" : "\(Int(count)) hours"
                case 5: duration = count * 60; label = "\(Int(count)) minutes"
                case 6: duration = count * 604_800; label = count == 1 ? "Week" : "\(Int(count)) weeks"
                default: break
                }
            }
            var reset = QuotaPayload.date(value["nextResetTime"])
            // Do not display an implausible five-hour reset as if its timezone were known.
            if duration == 18_000, let value = reset, value.timeIntervalSince(now) > 18_060 { reset = nil }
            let window = try UsageWindow(usedPercent: percent, resetsAt: reset, duration: duration)
            groups.append(QuotaGroup(id: "zai-\(index)", name: type == "TIME_LIMIT" ? "MCP tools" : "GLM Coding Plan",
                                     primary: window, primaryTitle: label))
        }
        guard !groups.isEmpty else { throw UsageError.noQuota }
        return ProviderUsage(id: .zai, subtitle: "Global · GLM Coding Plan", updatedAt: now, groups: groups)
    }
}
