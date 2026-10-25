import InvestmentSimulatorPresentation
import Testing

@MainActor
struct SettingsModelTests {
    @Test func `shows whether a key is stored`() {
        #expect(!SettingsModel(credentials: FakeCredentials()).hasStoredKey)
        #expect(SettingsModel(credentials: FakeCredentials("eq_old")).hasStoredKey)
    }

    /// Reading the secret can make macOS ask for Keychain access, which
    /// would block launch before any window opens.
    @Test func `checks for a stored key without reading it`() {
        let credentials = FakeCredentials("eq_old")

        _ = SettingsModel(credentials: credentials)

        #expect(credentials.keyReadCount == 0)
    }

    @Test func `saving stores the trimmed key and clears the field`() throws {
        let credentials = FakeCredentials()
        let model = SettingsModel(credentials: credentials)
        model.keyText = "  eq_new \n"

        model.save()

        #expect(try credentials.apiKey() == "eq_new")
        #expect(model.keyText.isEmpty)
        #expect(model.hasStoredKey)
        #expect(model.errorMessage == nil)
    }

    @Test func `a blank key can't be saved`() {
        let model = SettingsModel(credentials: FakeCredentials())
        model.keyText = "   "

        #expect(!model.canSave)
    }

    @Test func `removing the key forgets it`() throws {
        let credentials = FakeCredentials("eq_old")
        let model = SettingsModel(credentials: credentials)

        model.removeKey()

        #expect(try credentials.apiKey() == nil)
        #expect(!model.hasStoredKey)
    }

    @Test func `a failed save explains itself and keeps the field`() {
        let model = SettingsModel(credentials: FakeCredentials(failsToSave: true))
        model.keyText = "eq_new"

        model.save()

        #expect(model.errorMessage == "Couldn't save the API key in the Keychain.")
        #expect(model.keyText == "eq_new")
        #expect(!model.hasStoredKey)
    }
}
