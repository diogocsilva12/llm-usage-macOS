import Foundation

public enum AntigravityUsage {
    /// The CLI /usage command reports quota without issuing a model prompt.
    public static let arguments = ["-p", "/usage", "--output-format", "json"]

    public static func supportsUsageReport(version: String) -> Bool {
        guard let range = version.range(of: #"\b\d+\.\d+\.\d+\b"#, options: .regularExpression) else { return false }
        let parts = version[range].split(separator: ".").compactMap { Int($0) }
        return !parts.lexicographicallyPrecedes([1, 1, 11])
    }

    public static func parse(_ data: Data, now: Date = Date()) throws -> ProviderUsage {
        guard data.count <= 1_048_576 else { throw UsageError.outputTooLarge }
        let report: Report
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            report = try decoder.decode(Report.self, from: data)
        } catch { throw UsageError.invalidResponse }
        guard report.status == "SUCCESS", report.command.name == "usage" else { throw UsageError.commandFailed }

        var groups: [QuotaGroup] = []
        for (index, group) in (report.command.data.groups ?? []).enumerated() {
            var fiveHour: UsageWindow?
            var weekly: UsageWindow?
            for bucket in group.buckets ?? [] {
                guard bucket.disabled != true,
                      let fraction = bucket.remainingFraction ?? bucket.remaining?.fraction else { continue }
                guard fraction.isFinite, (0...1).contains(fraction) else { throw UsageError.invalidResponse }
                let period = cadence(bucket)
                guard period != nil else { continue }
                let window = try UsageWindow(usedPercent: (1 - fraction) * 100,
                    resetsAt: UsageDate.parse(bucket.resetTime), duration: period == "weekly" ? 604_800 : 18_000)
                if period == "weekly" {
                    if weekly == nil || window.usedPercent > weekly!.usedPercent { weekly = window }
                } else if fiveHour == nil || window.usedPercent > fiveHour!.usedPercent { fiveHour = window }
            }
            guard fiveHour != nil || weekly != nil else { continue }
            groups.append(QuotaGroup(id: "antigravity-\(index)", name: group.displayName ?? group.name ?? "Model quota",
                                     fiveHour: fiveHour, weekly: weekly))
        }
        guard !groups.isEmpty else { throw UsageError.noQuota }
        // Preserve separate model names, including Gemini 4 Argon allowances.
        return ProviderUsage(id: .antigravity, subtitle: "Signed-in Antigravity account", updatedAt: now, groups: groups)
    }

    private static func cadence(_ bucket: Bucket) -> String? {
        let explicit = bucket.window?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [explicit, bucket.bucketId, bucket.id, bucket.displayName, bucket.name]
            .compactMap { $0?.lowercased().replacingOccurrences(of: "_", with: "-") }
        if let explicit, !explicit.isEmpty { return classify(explicit) }
        return candidates.compactMap(classify).first
    }
    private static func classify(_ text: String) -> String? {
        if text == "weekly" || text.hasSuffix("-weekly") || text.contains("weekly limit") { return "weekly" }
        if ["5h", "5-hour", "five hour", "five-hour", "session"].contains(where: { text == $0 || text.hasSuffix("-\($0)") || text.contains("\($0) limit") }) { return "five-hour" }
        return nil
    }

    private struct Report: Decodable {
        let status: String
        let command: Command
        struct Command: Decodable { let name: String; let data: Payload }
        struct Payload: Decodable { let groups: [Group]? }
    }
    private struct Group: Decodable { let name: String?; let displayName: String?; let buckets: [Bucket]? }
    private struct Bucket: Decodable {
        let id: String?
        let bucketId: String?
        let name: String?
        let displayName: String?
        let window: String?
        let remainingFraction: Double?
        let remaining: Remaining?
        let resetTime: String?
        let disabled: Bool?
    }
    private struct Remaining: Decodable {
        let remainingFraction: Double?
        let value: Double?
        let `case`: String?
        var fraction: Double? { remainingFraction ?? (`case` == "remainingFraction" ? value : nil) }
    }
}
