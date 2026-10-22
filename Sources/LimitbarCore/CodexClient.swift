import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum CodexClient {
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        return URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    public static func fetch(credentials: CodexCredentials, session: URLSession) async throws -> ProviderUsage {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: CodexUsage.request(credentials: credentials)) }
        catch is CancellationError { throw CancellationError() }
        catch { throw UsageError.network }
        guard let response = response as? HTTPURLResponse else { throw UsageError.network }
        switch response.statusCode {
        case 200: return try CodexUsage.parse(data)
        case 401: throw UsageError.expiredSession
        case 403: throw UsageError.accessDenied
        case 429: throw UsageError.rateLimited
        default: throw UsageError.network
        }
    }
}
