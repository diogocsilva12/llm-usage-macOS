import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import LimitbarCore

private final class QuotaURLProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class QuotaAPIClientTests: XCTestCase {
    private let providers: [ProviderID] = [.claude, .copilot, .zai, .synthetic]
    override func setUp() {
        super.setUp()
        QuotaURLProtocol.status = 200
        QuotaURLProtocol.body = Data()
        QuotaURLProtocol.requests = []
    }
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QuotaURLProtocol.self]
        return URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    func testRequestsUseFixedHTTPSDestinationsAndCorrectAuthentication() throws {
        let urls: [ProviderID: String] = [
            .claude: "https://api.anthropic.com/api/oauth/usage",
            .copilot: "https://api.github.com/copilot_internal/user",
            .zai: "https://api.z.ai/api/monitor/usage/quota/limit",
            .synthetic: "https://api.synthetic.new/v2/quotas",
        ]
        for provider in providers {
            let request = try QuotaAPIClient.request(provider: provider, token: "synthetic-secret")
            XCTAssertEqual(request.url?.absoluteString, urls[provider])
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "\(provider == .copilot ? "token" : "Bearer") synthetic-secret")
            XCTAssertFalse(request.url!.absoluteString.contains("synthetic-secret"))
        }
        let claude = try QuotaAPIClient.request(provider: .claude, token: "synthetic-secret")
        XCTAssertEqual(claude.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        let copilot = try QuotaAPIClient.request(provider: .copilot, token: "synthetic-secret")
        XCTAssertEqual(copilot.value(forHTTPHeaderField: "X-Github-Api-Version"), "2025-04-01")
    }

    func testUnsafeCredentialsAndUnsupportedRoutesAreRejectedBeforeSending() {
        for token in ["", "token\nInjected: value", "token with spaces"] {
            XCTAssertThrowsError(try QuotaAPIClient.request(provider: .zai, token: token)) {
                XCTAssertEqual($0 as? UsageError, .missingProviderCredential)
            }
        }
        XCTAssertThrowsError(try QuotaAPIClient.request(provider: .codex, token: "synthetic-secret"))
    }

    func testAllFourProvidersFetchAndParseTheirRepresentativeQuotas() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        for provider in providers {
            QuotaURLProtocol.body = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: provider.rawValue, withExtension: "json", subdirectory: "Fixtures")))
            let result = try await QuotaAPIClient.fetch(provider: provider, token: "synthetic-secret", session: session,
                                                       now: UsageDate.parse("2026-10-22T12:00:00Z")!)
            XCTAssertEqual(result.id, provider)
            XCTAssertNotNil(result.summary)
            XCTAssertFalse(result.groups.isEmpty)
        }
        XCTAssertEqual(QuotaURLProtocol.requests.count, 4)
    }

    func testAuthenticationFailuresAndRateLimitsAreNotShownAsZeroUsage() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        for (status, error) in [(401, UsageError.providerSessionExpired), (403, .accessDenied), (429, .rateLimited), (500, .network)] {
            QuotaURLProtocol.status = status
            QuotaURLProtocol.body = Data("private server diagnostics".utf8)
            do {
                _ = try await QuotaAPIClient.fetch(provider: .copilot, token: "synthetic-secret", session: session)
                XCTFail("Expected HTTP failure")
            } catch let actual { XCTAssertEqual(actual as? UsageError, error) }
        }
    }
}
