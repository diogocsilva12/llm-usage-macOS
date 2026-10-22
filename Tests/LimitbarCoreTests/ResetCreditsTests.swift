import Foundation
import XCTest
@testable import LimitbarCore

final class ResetCreditsTests: XCTestCase {
    private var now: Date { UsageDate.parse("2026-10-22T12:00:00Z")! }

    private func usage(summary: String?) throws -> ProviderUsage {
        let extra = summary.map { ",\"rate_limit_reset_credits\":\($0)" } ?? ""
        let data = Data("""
        {"rate_limit":{"primary_window":{"used_percent":77,"limit_window_seconds":18000}}\(extra)}
        """.utf8)
        return try CodexUsage.parse(data, now: now)
    }

    func testReadsAvailableCountFromUsageSummary() throws {
        let result = try usage(summary: #"{"available_count":3}"#)
        XCTAssertEqual(result.resetCredits?.availableCount, 3)
        XCTAssertNil(result.resetCredits?.nextExpiresAt)
        XCTAssertEqual(result.resetCredits?.availableText, "3 resets available")
    }

    func testMissingOrMalformedResetMetadataDoesNotBreakUsage() throws {
        for summary in [nil, "null", "{}", #"{"available_count":-1}"#, #"{"available_count":"unknown"}"#, "[]"] {
            let result = try usage(summary: summary)
            XCTAssertEqual(result.summary?.usedPercent, 77)
            XCTAssertNil(result.resetCredits)
        }
    }

    func testZeroAvailableIsDistinctFromNotReported() throws {
        let result = try usage(summary: #"{"available_count":0}"#)
        XCTAssertEqual(result.resetCredits?.availableText, "0 resets available")
        XCTAssertNil(result.resetCredits?.expirationText(at: now))
    }

    func testInventoryShowsFullResetsAndEarliestAvailableExpiry() throws {
        let data = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "codex-reset-credits", withExtension: "json", subdirectory: "Fixtures")))
        let result = try CodexResetCredits.parse(data, now: now)
        XCTAssertEqual(result.availableCount, 3, "Use available_count, not the five total inventory entries.")
        XCTAssertEqual(result.availableText, "3 full resets available")
        XCTAssertEqual(result.nextExpiresAt, UsageDate.parse("2026-10-23T19:26:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(result.expirationText(at: now, calendar: calendar, locale: Locale(identifier: "en_GB")),
                       "Next expires tomorrow 19:26")
    }

    func testExpirationUsesTheMacTimeZone() throws {
        let data = Data(#"{"available_count":1,"credits":[{"reset_type":"codex_rate_limits","status":"available","expires_at":"2026-10-23T01:00:00Z"}]}"#.utf8)
        let result = try CodexResetCredits.parse(data, now: now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(result.expirationText(at: now, calendar: calendar, locale: Locale(identifier: "en_GB")),
                       "Next expires today 18:00")
        XCTAssertEqual(result.availableText, "1 full reset available")
    }

    func testExpiredSnapshotRequestsRefreshInsteadOfContinuingToClaimAvailability() throws {
        let data = Data(#"{"available_count":1,"credits":[{"reset_type":"codex_rate_limits","status":"available","expires_at":"2026-10-22T12:01:00Z"}]}"#.utf8)
        let result = try CodexResetCredits.parse(data, now: now)
        XCTAssertFalse(result.needsRefresh(at: now))
        XCTAssertTrue(result.needsRefresh(at: now.addingTimeInterval(61)))
        XCTAssertEqual(result.expirationText(at: now.addingTimeInterval(61)), "Refresh to update available resets")
    }

    func testPartialOrUnknownInventoryDoesNotInventAnExpiry() throws {
        for credit in [
            #"{"reset_type":"codex_rate_limits","status":"available","expires_at":"not-a-date"}"#,
            #"{"reset_type":"unknown_reset_type","status":"available","expires_at":"2026-10-23T19:26:00Z"}"#,
            #"{"reset_type":"codex_rate_limits","status":"available","expires_at":"2026-10-21T19:26:00Z"}"#,
        ] {
            let result = try CodexResetCredits.parse(Data("{\"available_count\":1,\"credits\":[\(credit)]}".utf8), now: now)
            XCTAssertNil(result.nextExpiresAt)
        }
        let partial = try CodexResetCredits.parse(Data(#"{"available_count":3,"credits":[]}"#.utf8), now: now)
        XCTAssertEqual(partial.availableCount, 3)
        XCTAssertFalse(partial.fullResets)
        XCTAssertEqual(partial.expirationText(at: now), "Expiration not reported")
    }

    func testInvalidInventoryIsRejected() {
        for json in [#"{"available_count":-1,"credits":[]}"#, #"{"credits":[]}"#, "not-json"] {
            XCTAssertThrowsError(try CodexResetCredits.parse(Data(json.utf8), now: now)) {
                XCTAssertEqual($0 as? UsageError, .invalidResponse)
            }
        }
    }
}
