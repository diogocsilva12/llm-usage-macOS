import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum QuotaAPIClient {
    public static func request(provider: ProviderID, token: String) throws -> URLRequest {
        guard !token.isEmpty, token.count <= 65_536, !token.contains(where: { $0.isWhitespace }) else {
            throw UsageError.missingProviderCredential
        }
        let url: String
        switch provider {
        case .claude: url = "https://api.anthropic.com/api/oauth/usage"
        case .copilot: url = "https://api.github.com/copilot_internal/user"
        case .zai: url = "https://api.z.ai/api/monitor/usage/quota/limit"
        case .synthetic: url = "https://api.synthetic.new/v2/quotas"
        default: throw UsageError.invalidResponse
        }
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("\(provider == .copilot ? "token" : "Bearer") \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Limitbar/1.1.0", forHTTPHeaderField: "User-Agent")
        if provider == .claude { request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta") }
        if provider == .copilot {
            request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
            request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
            request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
        }
        return request
    }

    public static func fetchClaude(credentials: ClaudeCredentials, session: URLSession, now: Date = Date()) async throws -> ProviderUsage {
        try await fetch(provider: .claude, token: credentials.accessToken, session: session, plan: credentials.plan, now: now)
    }

    public static func fetch(provider: ProviderID, token: String, session: URLSession,
                              plan: String? = nil, now: Date = Date()) async throws -> ProviderUsage {
        let request = try request(provider: provider, token: token)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { try Task.checkCancellation(); throw UsageError.network }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw UsageError.network }
        switch response.statusCode {
        case 200: break
        case 401: throw UsageError.providerSessionExpired
        case 403: throw UsageError.accessDenied
        case 429: throw UsageError.rateLimited
        default: throw UsageError.network
        }
        switch provider {
        case .claude: return try ClaudeUsage.parse(data, plan: plan, now: now)
        case .copilot: return try CopilotUsage.parse(data, now: now)
        case .zai: return try ZaiUsage.parse(data, now: now)
        case .synthetic: return try SyntheticUsage.parse(data, now: now)
        default: throw UsageError.invalidResponse
        }
    }
}
