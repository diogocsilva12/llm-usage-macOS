import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import LimitbarCore

private final class UsageURLProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class CodexClientTests: XCTestCase {
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
}
