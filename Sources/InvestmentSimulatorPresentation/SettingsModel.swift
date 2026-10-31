import Foundation
import InvestmentSimulatorCore
import Observation

/// Drives the Settings window: the Equibles API key and the SEC contact
/// email. Neither is shown once stored, only whether there is one: reading
/// either can make macOS ask for Keychain access.
@Observable
public final class SettingsModel {
    public var keyText = ""
    public private(set) var hasStoredKey: Bool
    public private(set) var errorMessage: String?
    public var emailText = ""
    public private(set) var hasStoredEmail: Bool
    public private(set) var emailErrorMessage: String?

    private let credentials: any CredentialStoring
    private let contactEmails: any ContactEmailStoring

    public init(credentials: any CredentialStoring, contactEmails: any ContactEmailStoring) {
        self.credentials = credentials
        self.contactEmails = contactEmails
        hasStoredKey = (try? credentials.hasAPIKey()) == true
        hasStoredEmail = (try? contactEmails.hasContactEmail()) == true
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

    private var trimmedEmail: String {
        emailText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Checks only the address's shape; nothing is sent to verify it
    /// (ADR-0019). It goes in a request header, so it can't hold whitespace.
    public var canSaveEmail: Bool {
        trimmedEmail.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }

    public var emailMessage: String? {
        trimmedEmail.isEmpty || canSaveEmail ? nil : "Enter an email address, such as you@example.com."
    }

    public func saveEmail() {
        guard canSaveEmail else {
            return
        }
        do {
            try contactEmails.setContactEmail(trimmedEmail)
            emailText = ""
            hasStoredEmail = true
            emailErrorMessage = nil
        } catch {
            emailErrorMessage = "Couldn't save the email in the Keychain."
        }
    }

    public func removeEmail() {
        do {
            try contactEmails.setContactEmail(nil)
            hasStoredEmail = false
            emailErrorMessage = nil
        } catch {
            emailErrorMessage = "Couldn't remove the email from the Keychain."
        }
    }
}
