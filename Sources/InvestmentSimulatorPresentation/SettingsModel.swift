import Foundation
import InvestmentSimulatorCore
import Observation

/// Drives the Settings window: the Equibles API key and the SEC contact
/// email. The API key is never read back, only whether there is one, because
/// reading a secret can make macOS ask for Keychain access. The email is read
/// once, by `loadStoredEmail()`, so the field can show it.
@Observable
public final class SettingsModel {
    public var keyText = ""
    public private(set) var hasStoredKey: Bool
    public private(set) var errorMessage: String?
    public var emailText = ""
    public private(set) var hasStoredEmail: Bool
    public private(set) var emailErrorMessage: String?

    /// The address last read from or written to the Keychain this session.
    private var savedEmail: String?

    private let credentials: any CredentialStoring
    private let contactEmails: any ContactEmailStoring

    public init(credentials: any CredentialStoring, contactEmails: any ContactEmailStoring) {
        self.credentials = credentials
        self.contactEmails = contactEmails
        hasStoredKey = (try? credentials.hasAPIKey()) == true
        do {
            hasStoredEmail = try contactEmails.hasContactEmail()
        } catch {
            hasStoredEmail = false
            emailErrorMessage = "Couldn't check the Keychain for a saved email."
        }
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
    /// (ADR-0019). It goes in a request header, so it can't hold whitespace
    /// or anything beyond ASCII.
    private var emailLooksValid: Bool {
        trimmedEmail.allSatisfy(\.isASCII) && trimmedEmail.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }

    /// False while the field still holds what is already stored.
    public var canSaveEmail: Bool {
        emailLooksValid && trimmedEmail != savedEmail
    }

    public var emailMessage: String? {
        trimmedEmail.isEmpty || emailLooksValid ? nil : "Enter an email address, such as you@example.com."
    }

    /// Fills the email field with the stored address. The email is the one
    /// secret shown back to the user, so this reads the Keychain item; the
    /// Settings window calls it when it appears, not at launch. Typed text
    /// is never overwritten.
    public func loadStoredEmail() {
        guard hasStoredEmail, emailText.isEmpty else {
            return
        }
        do {
            guard let email = try contactEmails.contactEmail() else {
                return
            }
            emailText = email
            savedEmail = email
            emailErrorMessage = nil
        } catch {
            emailErrorMessage = "Couldn't read the saved email from the Keychain."
        }
    }

    public func saveEmail() {
        guard canSaveEmail else {
            return
        }
        do {
            try contactEmails.setContactEmail(trimmedEmail)
            emailText = trimmedEmail
            savedEmail = trimmedEmail
            hasStoredEmail = true
            emailErrorMessage = nil
        } catch {
            emailErrorMessage = "Couldn't save the email in the Keychain."
        }
    }

    public func removeEmail() {
        do {
            try contactEmails.setContactEmail(nil)
            emailText = ""
            savedEmail = nil
            hasStoredEmail = false
            emailErrorMessage = nil
        } catch {
            emailErrorMessage = "Couldn't remove the email from the Keychain."
        }
    }
}
