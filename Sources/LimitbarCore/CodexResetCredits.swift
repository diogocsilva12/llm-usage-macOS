import Foundation

public struct ResetCredits: Equatable, Sendable {
    public let availableCount: Int
    public let nextExpiresAt: Date?
    public let fullResets: Bool

    public var availableText: String {
        let kind = fullResets ? "full reset" : "reset"
        return "\(availableCount) \(kind)\(availableCount == 1 ? "" : "s") available"
    }

    /// Inventory must be fetched again after a known credit expires.
    public func needsRefresh(at now: Date) -> Bool {
        nextExpiresAt.map { $0 <= now } ?? false
    }

    public func expirationText(at now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard availableCount > 0 else { return nil }
        guard let expiry = nextExpiresAt else { return "Expiration not reported" }
        guard expiry > now else { return "Refresh to update available resets" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        let time = formatter.string(from: expiry)
        if calendar.isDate(expiry, inSameDayAs: now) { return "Next expires today \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(expiry, inSameDayAs: tomorrow) { return "Next expires tomorrow \(time)" }
        formatter.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        return "Next expires \(formatter.string(from: expiry))"
    }
}

public enum CodexResetCredits {
    /// Read-only inventory returned by GET /wham/rate-limit-reset-credits.
    public static func parse(_ data: Data, now: Date = Date()) throws -> ResetCredits {
        guard data.count <= 1_048_576 else { throw UsageError.outputTooLarge }
        let payload: Inventory
        do { payload = try JSONDecoder().decode(Inventory.self, from: data) }
        catch { throw UsageError.invalidResponse }
        guard payload.available_count >= 0 else { throw UsageError.invalidResponse }
        let available = payload.credits.filter { credit in
            guard credit.status == "available", credit.reset_type == "codex_rate_limits" else { return false }
            if let expiry = credit.expires_at, let date = UsageDate.parse(expiry) { return date > now }
            return true
        }
        // Only claim full-reset semantics / a next expiry when this inventory accounts for the total.
        let complete = available.count == payload.available_count
        let datesValid = available.allSatisfy { $0.expires_at == nil || UsageDate.parse($0.expires_at) != nil }
        let next = complete && datesValid
            ? available.compactMap { UsageDate.parse($0.expires_at) }.min() : nil
        return ResetCredits(availableCount: payload.available_count, nextExpiresAt: next,
                            fullResets: complete && payload.available_count > 0)
    }

    private struct Inventory: Decodable {
        let available_count: Int
        let credits: [Credit]
    }
    private struct Credit: Decodable {
        let reset_type: String
        let status: String
        let expires_at: String?
    }
}
