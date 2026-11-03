/// Driven port for the contact email SEC EDGAR requires (ADR-0019).
/// Synchronous, and a read can wait on a Keychain access prompt, so a
/// caller on the main actor must run it elsewhere.
public protocol ContactEmailStoring: Sendable {
    func contactEmail() throws -> String?
    /// Whether an email is stored, without reading it.
    func hasContactEmail() throws -> Bool
    /// Saves `email`, or removes the stored email when it is nil.
    func setContactEmail(_ email: String?) throws
}
