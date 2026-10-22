import Foundation
import Security
import CryptoKit
import LimitbarCore

struct SourceSettings: Sendable {
    var codexHome: URL
    var antigravityExecutable: URL?
}

enum ProviderService {
    static func fetch(_ id: ProviderID, settings: SourceSettings) async throws -> ProviderUsage {
        switch id {
        case .codex:
            let credentials = try await Task.detached(priority: .utility) {
                try readCodexCredentials(home: settings.codexHome)
            }.value
            try Task.checkCancellation()
            let session = CodexClient.makeSession()
            defer { session.invalidateAndCancel() }
            return try await CodexClient.fetch(credentials: credentials, session: session)
        case .antigravity:
            guard let executable = settings.antigravityExecutable ?? discoverAntigravity(),
                  FileManager.default.isExecutableFile(atPath: executable.path) else { throw UsageError.cliMissing }
            let inherited = ProcessInfo.processInfo.environment
            var environment: [String: String] = [:]
            for key in ["HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "TMPDIR", "HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY"] {
                environment[key] = inherited[key]
            }
            environment["PATH"] = executable.deletingLastPathComponent().path + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            let version = try await CommandRunner.run(executable: executable, arguments: ["--version"],
                timeout: 5, environment: environment, guardBrowser: true)
            guard AntigravityUsage.supportsUsageReport(version: String(decoding: version, as: UTF8.self)) else {
                throw UsageError.cliOutdated
            }
            let report = try await CommandRunner.run(executable: executable, arguments: AntigravityUsage.arguments,
                timeout: 60, environment: environment, guardBrowser: true)
            return try AntigravityUsage.parse(report)
        }
    }

    static func discoverAntigravity() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/agy", "/usr/local/bin/agy", "\(home)/.local/bin/agy",
            "/Applications/Antigravity.app/Contents/Resources/app/bin/agy",
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    private static func readCodexCredentials(home: URL) throws -> CodexCredentials {
        let mode = credentialMode(home: home)
        if mode == "keyring" || mode == "auto" {
            if let data = try keychainData(home: home) { return try CodexCredentials.decode(data) }
            if mode == "keyring" { throw UsageError.notSignedIn }
        }
        let path = home.appendingPathComponent("auth.json")
        if FileManager.default.fileExists(atPath: path.path) {
            do {
                let handle = try FileHandle(forReadingFrom: path)
                defer { try? handle.close() }
                return try CodexCredentials.decode(handle.read(upToCount: 1_048_577) ?? Data())
            } catch let error as UsageError { throw error }
            catch { throw UsageError.notSignedIn }
        }
        if mode != "auto", let data = try keychainData(home: home) { return try CodexCredentials.decode(data) }
        throw UsageError.notSignedIn
    }

    private static func credentialMode(home: URL) -> String {
        // This is a top-level Codex setting. Stop at the first TOML table.
        guard let config = try? String(contentsOf: home.appendingPathComponent("config.toml"), encoding: .utf8) else { return "file" }
        for line in config.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("[") { break }
            guard text.hasPrefix("cli_auth_credentials_store"), let equal = text.firstIndex(of: "=") else { continue }
            let value = text[text.index(after: equal)...].split(separator: "#", maxSplits: 1).first ?? ""
            return value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
        }
        return "file"
    }

    private static func keychainData(home: URL) throws -> Data? {
        let canonical = home.resolvingSymlinksInPath().standardizedFileURL.path
        let hash = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Codex Auth",
            kSecAttrAccount as String: "cli|\(hash.prefix(16))",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw UsageError.keychainDenied }
        return data
    }
}
