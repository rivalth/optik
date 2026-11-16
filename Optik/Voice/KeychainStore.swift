import Foundation
import Security

/// API keys live only in the Keychain (`CLAUDE.md`). Never log a value.
enum APIKey: String, CaseIterable, Sendable {
    case anthropic = "anthropic-api-key"
    case elevenLabs = "elevenlabs-api-key"
}

enum KeychainStore {
    private static let service = "io.github.rivalth.optik"

    static func read(_ key: APIKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty
        else { return nil }
        return value
    }

    /// Saves the key, or deletes it when `value` is empty.
    @discardableResult
    static func write(_ value: String, for key: APIKey) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        var item = base
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func has(_ key: APIKey) -> Bool { read(key) != nil }
}
