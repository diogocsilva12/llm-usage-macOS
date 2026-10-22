import Foundation
import XCTest
@testable import LimitbarCore

final class UsageParsingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }
    private func data(_ text: String) -> Data { Data(text.utf8) }
    private func report(buckets: String, status: String = "SUCCESS", command: String = "usage") -> Data {
        data("""
        {"status":"\(status)","command":{"name":"\(command)","data":{"groups":[{"name":"Argon","buckets":\(buckets)}]}}}
        """)
    }

    func testCodexUsageAndResetDates() throws {
        let date = Date(timeIntervalSince1970: 100)
        let result = try CodexUsage.parse(fixture("codex"), now: date)
        XCTAssertEqual(result.id, .codex)
        XCTAssertEqual(result.subtitle, "ChatGPT · Plus")
        XCTAssertEqual(result.updatedAt, date)
        XCTAssertEqual(result.groups.first?.fiveHour?.usedPercent, 6)
        XCTAssertEqual(result.groups.first?.weekly?.usedPercent, 32)
        XCTAssertEqual(result.groups.first?.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1792703400))
    }

    func testCodexClassifiesReversedWindowsByDuration() throws {
        let result = try CodexUsage.parse(data("""
        {"rate_limit":{"primary_window":{"used_percent":41,"limit_window_seconds":604800},
        "secondary_window":{"used_percent":7,"limit_window_seconds":18000}}}
        """))
        XCTAssertEqual(result.groups[0].fiveHour?.usedPercent, 7)
        XCTAssertEqual(result.groups[0].weekly?.usedPercent, 41)
    }

    func testMissingCodexUsageIsNotZero() {
        XCTAssertThrowsError(try CodexUsage.parse(data("""
        {"rate_limit":{"primary_window":{"limit_window_seconds":18000}}}
        """))) { XCTAssertEqual($0 as? UsageError, .noQuota) }
    }

    func testUnknownCodexWindowIsNotMislabelled() {
        XCTAssertThrowsError(try CodexUsage.parse(data("""
        {"rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":86400}}}
        """))) { XCTAssertEqual($0 as? UsageError, .noQuota) }
    }

    func testCodexAdditionalModelLimitsAreKept() throws {
        let result = try CodexUsage.parse(data("""
        {"additional_rate_limits":[{"limit_name":"Extra model","rate_limit":{
          "primary_window":{"used_percent":25,"limit_window_seconds":18000}}}]}
        """))
        XCTAssertEqual(result.groups[0].name, "Extra model")
        XCTAssertEqual(result.groups[0].fiveHour?.usedPercent, 25)
    }

    func testArgonRemainsSeparateAndIsMenuSummary() throws {
        let result = try AntigravityUsage.parse(fixture("antigravity"))
        XCTAssertEqual(result.groups.count, 3)
        XCTAssertEqual(result.groups[1].name, "Gemini 4 Argon")
        XCTAssertNil(result.groups[1].fiveHour)
        XCTAssertEqual(result.groups[1].weekly?.usedPercent, 78)
        XCTAssertEqual(result.summary?.usedPercent, 78)
        XCTAssertNotNil(result.groups[1].weekly?.resetsAt)
        XCTAssertEqual(result.groups[0].fiveHour?.usedPercent, 0)
    }

    func testWeeklyOnlyStarterDoesNotInventSessionLimit() throws {
        let result = try AntigravityUsage.parse(report(buckets: """
        [{"id":"gemini-weekly","window":"weekly","remaining_fraction":1}]
        """))
        XCTAssertNil(result.groups[0].fiveHour)
        XCTAssertEqual(result.groups[0].weekly?.usedPercent, 0)
    }

    func testZeroRemainingMeansFullyUsed() throws {
        let result = try AntigravityUsage.parse(report(buckets: """
        [{"id":"gemini-5h","window":"5h","remaining_fraction":0}]
        """))
        XCTAssertEqual(result.groups[0].fiveHour?.usedPercent, 100)
    }

    func testUnavailableOrDisabledBucketsAreNotUsage() {
        for buckets in [
            #"[{"id":"gemini-weekly","window":"weekly"}]"#,
            #"[{"id":"gemini-weekly","window":"weekly","remaining_fraction":1,"disabled":true}]"#,
            #"[{"id":"gemini-weekly","window":"monthly","remaining_fraction":0.7}]"#,
        ] {
            XCTAssertThrowsError(try AntigravityUsage.parse(report(buckets: buckets))) {
                XCTAssertEqual($0 as? UsageError, .noQuota)
            }
        }
    }

    func testNestedCamelCaseQuotaAndCadenceFromID() throws {
        let result = try AntigravityUsage.parse(report(buckets: """
        [{"bucketId":"argon-weekly","remaining":{"case":"remainingFraction","value":0.7},
          "resetTime":"2026-10-25T15:59:00+01:00"}]
        """))
        XCTAssertEqual(try XCTUnwrap(result.groups[0].weekly?.usedPercent), 30, accuracy: 0.0001)
        XCTAssertNotNil(result.groups[0].weekly?.resetsAt)
    }

    func testDuplicateCadenceUsesMostConstrainedBucket() throws {
        let result = try AntigravityUsage.parse(report(buckets: """
        [{"window":"weekly","remaining_fraction":0.7},{"window":"weekly","remaining_fraction":0.2}]
        """))
        XCTAssertEqual(result.groups[0].weekly?.usedPercent, 80)
    }

    func testInvalidFractionsAreRejected() {
        for fraction in [-0.1, 1.1] {
            XCTAssertThrowsError(try AntigravityUsage.parse(report(buckets: """
            [{"window":"weekly","remaining_fraction":\(fraction)}]
            """))) { XCTAssertEqual($0 as? UsageError, .invalidResponse) }
        }
        XCTAssertThrowsError(try UsageWindow(usedPercent: .nan))
        XCTAssertThrowsError(try UsageWindow(usedPercent: 101))
    }

    func testOnlySuccessfulUsageCommandsAreAccepted() {
        for (status, command) in [("ERROR", "usage"), ("success", "usage"), ("SUCCESS", "models")] {
            XCTAssertThrowsError(try AntigravityUsage.parse(report(buckets: "[]", status: status, command: command))) {
                XCTAssertEqual($0 as? UsageError, .commandFailed)
            }
        }
    }

    func testCLICompatibilityGate() {
        XCTAssertFalse(AntigravityUsage.supportsUsageReport(version: "agy 1.1.10"))
        XCTAssertFalse(AntigravityUsage.supportsUsageReport(version: "unknown"))
        XCTAssertTrue(AntigravityUsage.supportsUsageReport(version: "agy 1.1.11"))
        XCTAssertTrue(AntigravityUsage.supportsUsageReport(version: "1.2.11"))
        XCTAssertTrue(AntigravityUsage.supportsUsageReport(version: "Antigravity 2.0.0"))
    }

    func testOversizedAndMalformedReportsAreRejected() {
        XCTAssertThrowsError(try AntigravityUsage.parse(Data(repeating: 32, count: 1_048_577))) {
            XCTAssertEqual($0 as? UsageError, .outputTooLarge)
        }
        XCTAssertThrowsError(try CodexUsage.parse(data("not JSON"))) {
            XCTAssertEqual($0 as? UsageError, .invalidResponse)
        }
    }

    func testStaleDataUsesActualTimestamp() throws {
        let date = Date(timeIntervalSince1970: 100)
        let result = try CodexUsage.parse(fixture("codex"), now: date)
        XCTAssertFalse(result.isStale(at: date.addingTimeInterval(300)))
        XCTAssertTrue(result.isStale(at: date.addingTimeInterval(901)))
    }
}
