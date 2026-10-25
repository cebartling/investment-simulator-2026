import Foundation
import InvestmentSimulatorCore
import Observation

/// Drives the Settings window: the Equibles API key. A stored key is never
/// shown, only whether there is one.
@Observable
public final class SettingsModel {
    public var keyText = ""
    public private(set) var hasStoredKey: Bool
    public private(set) var errorMessage: String?

    private let credentials: any CredentialStoring

    public init(credentials: any CredentialStoring) {
        self.credentials = credentials
        hasStoredKey = (try? credentials.hasAPIKey()) == true
    }

    private var trimmedKey: String {
        keyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var canSave: Bool {
        !trimmedKey.isEmpty
    }

    public func save() {
        guard canSave else {
            return
        }
        do {
            try credentials.setAPIKey(trimmedKey)
            keyText = ""
            hasStoredKey = true
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't save the API key in the Keychain."
        }
    }

    public func removeKey() {
        do {
            try credentials.setAPIKey(nil)
            hasStoredKey = false
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't remove the API key from the Keychain."
        }
    }
}
