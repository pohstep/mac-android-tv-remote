import Foundation
import Security

enum KeychainError: Error, CustomStringConvertible {
    case status(OSStatus)

    var description: String {
        "The Keychain returned status \(statusCode)."
    }

    private var statusCode: OSStatus {
        switch self {
        case .status(let code): return code
        }
    }
}

/// Generic password for a Sony pre-shared key. The value is never included in errors.
struct KeychainStore {
    static let service = "app.pohstep.remote"
    /// v1.0 stored the only key here. New TVs use `psk.<device id>`.
    static let legacyAccount = "bravia-psk"
    static let account = legacyAccount

    func account(for deviceID: String) -> String {
        let trimmed = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return Self.legacyAccount }
        return "psk.\(trimmed)"
    }

    func load() -> String {
        load(account: Self.legacyAccount)
    }

    func load(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    func save(_ value: String) throws {
        try save(value, account: Self.legacyAccount)
    }

    func save(_ value: String, account: String) throws {
        clear(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
    }

    func clear() {
        clear(account: Self.legacyAccount)
    }

    func clear(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
