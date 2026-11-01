import Foundation
import InvestmentSimulatorCore
import Security

/// Keeps the Equibles API key as a generic password in the login Keychain
/// (ADR-0012), never in documents or `UserDefaults`.
struct KeychainCredentialStore: CredentialStoring {
    private let item = KeychainItem(account: "equibles-api-key")

    func apiKey() throws -> String? {
        try item.value()
    }

    func hasAPIKey() throws -> Bool {
        try item.exists()
    }

    func setAPIKey(_ key: String?) throws {
        try item.setValue(key)
    }
}

/// Keeps the SEC contact email the same way (ADR-0019).
struct KeychainContactEmailStore: ContactEmailStoring {
    private let item = KeychainItem(account: "sec-contact-email")

    func contactEmail() throws -> String? {
        try item.value()
    }

    func hasContactEmail() throws -> Bool {
        try item.exists()
    }

    func setContactEmail(_ email: String?) throws {
        try item.setValue(email)
    }
}

/// One generic password in the login Keychain.
private nonisolated struct KeychainItem {
    private let service = "com.cebartling.InvestmentSimulator"
    let account: String

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func value() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(bytes: data, encoding: .utf8) else {
                throw KeychainError(status: errSecDecode)
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    /// Asks for the item's attributes only. Reading the secret can make macOS
    /// prompt for access, for example after a rebuild changes the signature.
    func exists() throws -> Bool {
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

    func setValue(_ value: String?) throws {
        guard let value else {
            let deleted = SecItemDelete(baseQuery as CFDictionary)
            guard deleted == errSecSuccess || deleted == errSecItemNotFound else {
                throw KeychainError(status: deleted)
            }
            return
        }
        // Replace the value in place, so a failed save keeps the old one.
        let data = Data(value.utf8)
        let updated = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch updated {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else {
                throw KeychainError(status: added)
            }
        default:
            throw KeychainError(status: updated)
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
