import Foundation
import Security
import LimitbarCore

/// Only credentials explicitly entered in Limitbar are written to this service.
enum ProviderKeychain {
    private static func query(_ provider: ProviderID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.diogocsilva.limitbar.provider-token",
         kSecAttrAccount as String: provider.rawValue]
    }

    static func contains(_ provider: ProviderID) -> Bool {
        var query = query(provider)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(_ provider: ProviderID) throws -> String {
        var query = query(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { throw UsageError.missingProviderCredential }
        guard status == errSecSuccess else { throw UsageError.keychainDenied }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw UsageError.missingProviderCredential
        }
        return token
    }

    static func save(_ token: String, provider: ProviderID) throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.count <= 65_536, !token.contains(where: { $0.isWhitespace }) else {
            throw UsageError.missingProviderCredential
        }
        let update = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query(provider) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw UsageError.keychainWriteFailed }
        var addition = query(provider)
        addition[kSecValueData as String] = Data(token.utf8)
        addition[kSecAttrLabel as String] = "Limitbar · \(provider.title)"
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else { throw UsageError.keychainWriteFailed }
    }

    static func delete(_ provider: ProviderID) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw UsageError.keychainWriteFailed }
    }
}
