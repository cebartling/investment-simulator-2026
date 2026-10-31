/// Driven port for the contact email SEC EDGAR requires (ADR-0019).
/// Synchronous: the Keychain answers immediately.
public protocol ContactEmailStoring: Sendable {
    func contactEmail() throws -> String?
    /// Whether an email is stored, without reading it.
    func hasContactEmail() throws -> Bool
    /// Saves `email`, or removes the stored email when it is nil.
    func setContactEmail(_ email: String?) throws
}
