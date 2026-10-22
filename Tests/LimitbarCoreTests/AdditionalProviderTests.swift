import Foundation
import XCTest
@testable import LimitbarCore

final class AdditionalProviderTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }
    private func data(_ json: String) -> Data { Data(json.utf8) }
    private var now: Date { UsageDate.parse("2026-10-22T12:00:00Z")! }

    func testClaudeSubscriptionAndModelWindows() throws {
        let result = try ClaudeUsage.parse(fixture("claude"), plan: "max", now: now)
        XCTAssertEqual(result.id, .claude)
        XCTAssertEqual(result.subtitle, "Claude · Max")
        XCTAssertEqual(result.groups.count, 2)
        XCTAssertEqual(result.groups[0].fiveHour?.usedPercent, 19.5)
        XCTAssertEqual(result.groups[0].weekly?.usedPercent, 41)
        XCTAssertNil(result.groups[1].fiveHour)
        XCTAssertEqual(result.groups[1].weekly?.usedPercent, 13)
        XCTAssertNotNil(result.groups[0].fiveHour?.resetsAt)
    }

    func testClaudeOAuthCredentialFormatAndAPIKeyRejection() throws {
        let credentials = try ClaudeCredentials.decode(data(#"{"claudeAiOauth":{"accessToken":"synthetic-oauth-token","subscriptionType":"pro"}}"#))
        XCTAssertEqual(credentials.plan, "pro")
        for json in [#"{"apiKey":"synthetic-key"}"#, #"{"claudeAiOauth":{"accessToken":""}}"#, "{}"] {
            XCTAssertThrowsError(try ClaudeCredentials.decode(data(json))) { XCTAssertEqual($0 as? UsageError, .claudeNotSignedIn) }
        }
    }

    func testClaudeMissingWindowsAreNotZero() throws {
        let result = try ClaudeUsage.parse(data(#"{"seven_day":{"utilization":0}}"#))
        XCTAssertNil(result.groups[0].fiveHour)
        XCTAssertEqual(result.groups[0].weekly?.usedPercent, 0)
        XCTAssertThrowsError(try ClaudeUsage.parse(data(#"{"five_hour":{"resets_at":null}}"#))) { XCTAssertEqual($0 as? UsageError, .noQuota) }
    }

    func testCopilotMonthlyQuotaAndUnlimitedNotes() throws {
        let result = try CopilotUsage.parse(fixture("copilot"), now: now)
        XCTAssertEqual(result.groups[0].primary?.usedPercent, 25)
        XCTAssertEqual(result.groups[0].primaryTitle, "Premium / month")
        XCTAssertNil(result.groups[0].fiveHour, "Monthly usage must not masquerade as a five-hour allowance.")
        XCTAssertNil(result.groups[0].weekly)
        XCTAssertNil(result.groups[0].secondary)
        XCTAssertEqual(result.notes, ["Chat: unlimited", "Completions: unlimited"])
        XCTAssertEqual(result.summary?.usedPercent, 25)
    }

    func testCopilotDerivesPercentWhenOnlyCountsAreReported() throws {
        let result = try CopilotUsage.parse(data(#"{"quota_snapshots":{"premium_interactions":{"entitlement":"300","remaining":"150"}}}"#))
        XCTAssertEqual(result.summary?.usedPercent, 50)
    }

    func testCopilotZeroEntitlementIsNotAQuotaBar() throws {
        let result = try CopilotUsage.parse(data(#"{"token_based_billing":true,"quota_snapshots":{"premium_interactions":{"entitlement":0,"remaining":0,"percent_remaining":100}}}"#))
        XCTAssertTrue(result.groups.isEmpty)
        XCTAssertNil(result.summary)
        XCTAssertFalse(result.notes.isEmpty)
    }

    func testCopilotUnlimitedOnlyAccountHasNoInventedUsage() throws {
        let result = try CopilotUsage.parse(data(#"{"quota_snapshots":{"chat":{"unlimited":true}}}"#))
        XCTAssertTrue(result.groups.isEmpty)
        XCTAssertEqual(result.notes, ["Chat: unlimited"])
        XCTAssertThrowsError(try CopilotUsage.parse(data(#"{"quota_snapshots":{"premium_interactions":{}}}"#))) {
            XCTAssertEqual($0 as? UsageError, .noQuota)
        }
    }

    func testZaiFiveHourAndMonthlyMCPPeriods() throws {
        let result = try ZaiUsage.parse(fixture("zai"), now: now)
        XCTAssertEqual(result.groups.count, 2)
        XCTAssertEqual(result.groups[0].primary?.usedPercent, 20, "Measured counters override a stale rounded percentage.")
        XCTAssertEqual(result.groups[0].primaryTitle, "5 hours")
        XCTAssertEqual(result.groups[1].primaryTitle, "Monthly")
        XCTAssertEqual(result.groups[1].name, "MCP tools")
        XCTAssertNil(result.groups[1].fiveHour)
    }

    func testZaiUnknownPeriodsAreNotLabelledFiveHours() throws {
        let result = try ZaiUsage.parse(data(#"{"success":true,"code":200,"data":{"limits":[{"type":"CREDIT_LIMIT","percentage":10,"unit":99,"number":1}]}}"#))
        XCTAssertEqual(result.groups[0].primaryTitle, "Quota")
        XCTAssertNil(result.groups[0].primary?.duration)
    }

    func testZaiImplausibleResetTimestampIsNotTimezoneCorrected() throws {
        let reset = now.addingTimeInterval(10 * 3600).timeIntervalSince1970 * 1000
        let result = try ZaiUsage.parse(data("""
        {"success":true,"code":200,"data":{"limits":[{"type":"TOKENS_LIMIT","percentage":10,"unit":3,"number":5,"nextResetTime":\(reset)}]}}
        """), now: now)
        XCTAssertNil(result.groups[0].primary?.resetsAt)
    }

    func testZaiErrorsAndEmptyPlansCannotBecomeZeroUsage() {
        for json in [#"{"success":false,"code":401,"data":{}}"#, #"{"success":true,"code":200,"data":{"limits":[]}}"#] {
            XCTAssertThrowsError(try ZaiUsage.parse(data(json)))
        }
    }

    func testZaiApplicationLayerAuthenticationFailureIsActionable() {
        XCTAssertThrowsError(try ZaiUsage.parse(data(#"{"success":false,"code":401}"#))) {
            XCTAssertEqual($0 as? UsageError, .providerSessionExpired)
        }
    }

    func testOutOfRangePeriodCannotCrashFormatting() {
        for count in ["1e100", "-1", "1.5"] {
            XCTAssertThrowsError(try ZaiUsage.parse(data("""
            {"success":true,"code":200,"data":{"limits":[{"type":"TOKENS_LIMIT","percentage":10,"unit":3,"number":\(count)}]}}
            """))) { XCTAssertEqual($0 as? UsageError, .invalidResponse) }
        }
        XCTAssertNil(QuotaPayload.date(1e100))
    }

    func testSyntheticKnownLanesAndActualPercentUnits() throws {
        let result = try SyntheticUsage.parse(fixture("synthetic"), now: now)
        XCTAssertEqual(result.groups[0].fiveHour?.usedPercent, 20)
        XCTAssertEqual(result.groups[0].weekly?.usedPercent, 99.5, "0.5 percent remaining means 99.5 percent used, not 50.")
        XCTAssertEqual(result.groups[1].primaryTitle, "Hourly")
        XCTAssertEqual(try XCTUnwrap(result.groups[1].primary?.usedPercent), 0.8, accuracy: 0.0001)
        XCTAssertNotNil(result.groups[1].primary?.resetsAt)
    }

    func testSyntheticDataEnvelopeAndMissingRollingWindow() throws {
        let result = try SyntheticUsage.parse(data(#"{"data":{"weeklyTokenLimit":{"percentRemaining":98}}}"#))
        XCTAssertNil(result.groups[0].fiveHour)
        XCTAssertEqual(result.groups[0].weekly?.usedPercent, 2)
    }

    func testSyntheticUnknownDenominatorIsNotZeroOrUnlimited() {
        XCTAssertThrowsError(try SyntheticUsage.parse(data(#"{"rollingFiveHourLimit":{"limit":0,"used":0}}"#))) {
            XCTAssertEqual($0 as? UsageError, .noQuota)
        }
    }

    func testBooleanQuotaValuesAreRejected() {
        XCTAssertThrowsError(try ClaudeUsage.parse(data(#"{"five_hour":{"utilization":true}}"#)))
        XCTAssertThrowsError(try CopilotUsage.parse(data(#"{"quota_snapshots":{"chat":{"percent_remaining":false}}}"#)))
        XCTAssertThrowsError(try SyntheticUsage.parse(data(#"{"weeklyTokenLimit":{"percentRemaining":true}}"#)))
    }

    func testInvalidPercentagesAndOversizedPayloadsAreRejected() {
        XCTAssertThrowsError(try ClaudeUsage.parse(data(#"{"five_hour":{"utilization":101}}"#)))
        XCTAssertThrowsError(try SyntheticUsage.parse(data(#"{"weeklyTokenLimit":{"percentRemaining":-1}}"#)))
        XCTAssertThrowsError(try CopilotUsage.parse(data(#"{"quota_snapshots":{"chat":{"percent_remaining":101}}}"#)))
        XCTAssertThrowsError(try SyntheticUsage.parse(Data(repeating: 32, count: 1_048_577))) {
            XCTAssertEqual($0 as? UsageError, .outputTooLarge)
        }
    }
}
