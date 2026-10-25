import Foundation
import InvestmentSimulatorCore
import Security

/// Keeps the Equibles API key as a generic password in the login Keychain
/// (ADR-0012), never in documents or `UserDefaults`.
struct KeychainCredentialStore: CredentialStoring {
    private let service = "com.cebartling.InvestmentSimulator"
    private let account = "equibles-api-key"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func apiKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let key = String(bytes: data, encoding: .utf8) else {
                throw KeychainError(status: errSecDecode)
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    /// Asks for the item's attributes only. Reading the secret can make macOS
    /// prompt for access, for example after a rebuild changes the signature.
    func hasAPIKey() throws -> Bool {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw KeychainError(status: status)
        }
    }

    func setAPIKey(_ key: String?) throws {
        let deleted = SecItemDelete(baseQuery as CFDictionary)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else {
            throw KeychainError(status: deleted)
        }
        guard let key else {
            return
        }
        var item = baseQuery
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else {
            throw KeychainError(status: added)
        }
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
        return "Keychain error \(status): \(message)"
    }
}
