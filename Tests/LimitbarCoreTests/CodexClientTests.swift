import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import LimitbarCore

private final class UsageURLProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    static var creditsStatus = 404
    static var creditsBody = Data()
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let isInventory = request.url?.path.hasSuffix("/rate-limit-reset-credits") == true
        let response = HTTPURLResponse(url: request.url!, statusCode: isInventory ? Self.creditsStatus : Self.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: isInventory ? Self.creditsBody : Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class CodexClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UsageURLProtocol.status = 200
        UsageURLProtocol.body = Data()
        UsageURLProtocol.creditsStatus = 404
        UsageURLProtocol.creditsBody = Data()
        UsageURLProtocol.requests = []
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }

    private func usageBody(count: Int?) throws -> Data {
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("codex")) as? [String: Any])
        if let count { body["rate_limit_reset_credits"] = ["available_count": count] }
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func credentials() throws -> CodexCredentials {
        try CodexCredentials.decode(Data(#"{"tokens":{"access_token":"synthetic-test-token","account_id":"test-account"}}"#.utf8))
    }

    func testRequestUsesReadOnlyAccountScopedEndpoint() throws {
        let request = CodexUsage.request(credentials: try credentials())
        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "test-account")
        XCTAssertNil(request.httpBody)
    }

    func testAPIKeysAndEmptySessionsAreRejected() {
        for json in [#"{"OPENAI_API_KEY":"synthetic"}"#, #"{"tokens":{"access_token":""}}"#, "{}"] {
            XCTAssertThrowsError(try CodexCredentials.decode(Data(json.utf8))) {
                XCTAssertEqual($0 as? UsageError, .notSignedIn)
            }
        }
    }

    func testSessionDisablesPersistentCookiesAndRedirects() throws {
        let session = CodexClient.makeSession()
        defer { session.invalidateAndCancel() }
        XCTAssertFalse(session.configuration.httpShouldSetCookies)
        XCTAssertNil(session.configuration.urlCache)
        let delegate = try XCTUnwrap(session.delegate as? NoRedirectDelegate)
        let request = CodexUsage.request(credentials: try credentials())
        let task = session.dataTask(with: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: "https://example.invalid")!)) { redirected in
                XCTAssertNil(redirected)
            }
    }

    func testFetchParsesSuccessfulResponseAndClassifiesFailures() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        UsageURLProtocol.status = 200
        UsageURLProtocol.body = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "codex", withExtension: "json", subdirectory: "Fixtures")))
        let usage = try await CodexClient.fetch(credentials: credentials(), session: session)
        XCTAssertEqual(usage.groups.first?.weekly?.usedPercent, 32)
        for (status, expected) in [(401, UsageError.expiredSession), (403, .accessDenied), (429, .rateLimited), (500, .network)] {
            UsageURLProtocol.status = status
            UsageURLProtocol.body = Data("private response details".utf8)
            do {
                _ = try await CodexClient.fetch(credentials: credentials(), session: session)
                XCTFail("Expected error for \(status)")
            } catch { XCTAssertEqual(error as? UsageError, expected) }
        }
    }

    func testFetchAddsResetCountAndExpiryUsingReadOnlyAccountScopedRequest() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        UsageURLProtocol.body = try usageBody(count: 3)
        UsageURLProtocol.creditsStatus = 200
        UsageURLProtocol.creditsBody = try fixture("codex-reset-credits")
        let result = try await CodexClient.fetch(credentials: credentials(), session: session,
                                                now: UsageDate.parse("2026-10-22T12:00:00Z")!)
        XCTAssertEqual(result.resetCredits?.availableText, "3 full resets available")
        XCTAssertEqual(result.resetCredits?.nextExpiresAt, UsageDate.parse("2026-10-23T19:26:00Z"))
        XCTAssertEqual(UsageURLProtocol.requests.map { $0.url?.path },
                       ["/backend-api/wham/usage", "/backend-api/wham/rate-limit-reset-credits"])
        for request in UsageURLProtocol.requests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.host, "chatgpt.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "test-account")
            XCTAssertNil(request.httpBody)
        }
    }

    func testInventoryFailurePreservesUsageAndSummaryCount() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        UsageURLProtocol.body = try usageBody(count: 3)
        for status in [401, 403, 404, 429, 500] {
            UsageURLProtocol.creditsStatus = status
            let result = try await CodexClient.fetch(credentials: credentials(), session: session)
            XCTAssertEqual(result.summary?.usedPercent, 6)
            XCTAssertEqual(result.resetCredits?.availableCount, 3)
            XCTAssertNil(result.resetCredits?.nextExpiresAt)
        }
    }

    func testMissingSummaryStillAllowsInventoryRead() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        UsageURLProtocol.body = try usageBody(count: nil)
        UsageURLProtocol.creditsStatus = 200
        UsageURLProtocol.creditsBody = try fixture("codex-reset-credits")
        let result = try await CodexClient.fetch(credentials: credentials(), session: session,
                                                now: UsageDate.parse("2026-10-22T12:00:00Z")!)
        XCTAssertEqual(result.resetCredits?.availableCount, 3)
        XCTAssertNotNil(result.resetCredits?.nextExpiresAt)
    }

    func testMalformedInventoryDoesNotHideUsage() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        UsageURLProtocol.body = try usageBody(count: 3)
        UsageURLProtocol.creditsStatus = 200
        UsageURLProtocol.creditsBody = Data("not-json".utf8)
        let result = try await CodexClient.fetch(credentials: credentials(), session: session)
        XCTAssertEqual(result.resetCredits?.availableCount, 3)
        XCTAssertEqual(result.groups.first?.weekly?.usedPercent, 32)
    }

    func testZeroResetsSkipsUnnecessaryInventoryRequest() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        UsageURLProtocol.body = try usageBody(count: 0)
        let result = try await CodexClient.fetch(credentials: credentials(), session: session)
        XCTAssertEqual(result.resetCredits?.availableText, "0 resets available")
        XCTAssertEqual(UsageURLProtocol.requests.count, 1)
    }
}
