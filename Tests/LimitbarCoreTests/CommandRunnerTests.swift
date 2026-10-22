import Foundation
import XCTest
@testable import LimitbarCore

final class CommandRunnerTests: XCTestCase {
    private let environment = ["PATH": "/usr/bin:/bin"]

    func testCapturesOutputAndDoesNotInterpretArguments() async throws {
        let output = try await CommandRunner.run(executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["%s", "$(not-a-command); literal"], timeout: 2, environment: environment)
        XCTAssertEqual(String(decoding: output, as: UTF8.self), "$(not-a-command); literal")
    }

    func testTimeoutTerminatesCommand() async {
        let start = Date()
        do {
            _ = try await CommandRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["10"], timeout: 0.1, environment: environment)
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? UsageError, .timedOut) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testLargeOutputFailsWithoutPipeDeadlock() async {
        do {
            _ = try await CommandRunner.run(executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "head -c 1100000 /dev/zero"], timeout: 2, environment: environment)
            XCTFail("Expected bounded output failure")
        } catch { XCTAssertEqual(error as? UsageError, .outputTooLarge) }
    }

    func testRawFailureOutputIsNeverExposed() async {
        do {
            _ = try await CommandRunner.run(executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf 'private diagnostic' >&2; exit 3"], timeout: 2, environment: environment)
            XCTFail("Expected command failure")
        } catch {
            XCTAssertEqual(error as? UsageError, .commandFailed)
            XCTAssertFalse(error.localizedDescription.contains("private diagnostic"))
        }
    }

    func testBrowserGuardAndPrivateWorkingDirectory() async throws {
        let output = try await CommandRunner.run(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "open 'https://example.invalid' >/dev/null 2>&1; test $? -eq 1 && pwd"],
            timeout: 2, environment: environment, guardBrowser: true)
        let directory = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(directory.contains("limitbar-"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory))
    }

    func testCancellationStopsCommand() async {
        let task = Task {
            try await CommandRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["10"], timeout: 10, environment: environment)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
