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

    #if ZAPBAR_MIGRATE_V1 && !SANDBOX_BUILD
    /// v1.0 stored the only key here. Release and sandbox builds do not compile this account.
    static let legacyAccount = "bravia-psk"
    static let account = legacyAccount

    func load() -> String {
        load(account: Self.legacyAccount)
    }

    func save(_ value: String) throws {
        try save(value, account: Self.legacyAccount)
    }

    func clear() {
        clear(account: Self.legacyAccount)
    }
    #endif

    func account(for deviceID: String) -> String {
        let trimmed = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        #if ZAPBAR_MIGRATE_V1 && !SANDBOX_BUILD
        if trimmed.isEmpty { return Self.legacyAccount }
        #endif
        if trimmed.isEmpty { return "" }
        return "psk.\(trimmed)"
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

    func clear(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
