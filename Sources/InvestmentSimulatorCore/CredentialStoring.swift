/// Driven port for the market data API key (ADR-0012). Synchronous: the
/// Keychain answers immediately.
public protocol CredentialStoring: Sendable {
    func apiKey() throws -> String?
    /// Saves `key`, or removes the stored key when it is nil.
    func setAPIKey(_ key: String?) throws
}
