import InvestmentSimulatorPresentation
import Testing

@MainActor
struct SettingsModelTests {
    @Test func `shows whether a key is stored`() {
        #expect(!settings(FakeCredentials()).hasStoredKey)
        #expect(settings(FakeCredentials("eq_old")).hasStoredKey)
    }

    /// Reading the secret can make macOS ask for Keychain access, which
    /// would block launch before any window opens.
    @Test func `checks for a stored key without reading it`() {
        let credentials = FakeCredentials("eq_old")

        _ = settings(credentials)

        #expect(credentials.keyReadCount == 0)
    }

    @Test func `saving stores the trimmed key and clears the field`() throws {
        let credentials = FakeCredentials()
        let model = settings(credentials)
        model.keyText = "  eq_new \n"

        model.save()

        #expect(try credentials.apiKey() == "eq_new")
        #expect(model.keyText.isEmpty)
        #expect(model.hasStoredKey)
        #expect(model.errorMessage == nil)
    }

    @Test func `a blank key can't be saved`() {
        let model = settings(FakeCredentials())
        model.keyText = "   "

        #expect(!model.canSave)
    }

    @Test func `removing the key forgets it`() throws {
        let credentials = FakeCredentials("eq_old")
        let model = settings(credentials)

        model.removeKey()

        #expect(try credentials.apiKey() == nil)
        #expect(!model.hasStoredKey)
    }

    @Test func `a failed save explains itself and keeps the field`() {
        let model = settings(FakeCredentials(failsToSave: true))
        model.keyText = "eq_new"

        model.save()

        #expect(model.errorMessage == "Couldn't save the API key in the Keychain.")
        #expect(model.keyText == "eq_new")
        #expect(!model.hasStoredKey)
    }

    @Test func `shows whether a contact email is stored, without reading it`() {
        let emails = FakeContactEmail("me@example.com")

        #expect(SettingsModel(credentials: FakeCredentials(), contactEmails: emails).hasStoredEmail)
        #expect(emails.readCount == 0)
        #expect(!model().hasStoredEmail)
    }

    @Test func `saving stores the trimmed email and clears the field`() throws {
        let emails = FakeContactEmail()
        let model = model(emails)
        model.emailText = "  me@example.com \n"

        model.saveEmail()

        #expect(try emails.contactEmail() == "me@example.com")
        #expect(model.emailText.isEmpty)
        #expect(model.hasStoredEmail)
        #expect(model.emailErrorMessage == nil)
    }

    @Test(arguments: ["", "   ", "me", "me@", "@example.com", "me@example", "me example@test.com", "me@a@b.com"])
    func `text that doesn't look like an email can't be saved`(text: String) throws {
        let emails = FakeContactEmail()
        let model = model(emails)
        model.emailText = text

        model.saveEmail()

        #expect(!model.canSaveEmail)
        #expect(try emails.contactEmail() == nil)
    }

    /// The address goes in a request header.
    @Test func `an email with a line break inside it can't be saved`() {
        let model = model()
        model.emailText = "me@example.com\r\nX-Other: 1"

        #expect(!model.canSaveEmail)
    }

    @Test func `says when typed text doesn't look like an email`() {
        let model = model()

        #expect(model.emailMessage == nil)
        model.emailText = "me"
        #expect(model.emailMessage == "Enter an email address, such as you@example.com.")
        model.emailText = "me@example.com"
        #expect(model.emailMessage == nil)
    }

    @Test func `removing the email forgets it`() throws {
        let emails = FakeContactEmail("me@example.com")
        let model = model(emails)

        model.removeEmail()

        #expect(try emails.contactEmail() == nil)
        #expect(!model.hasStoredEmail)
    }

    @Test func `a failed email save explains itself and keeps the field`() {
        let model = model(FakeContactEmail(failsToSave: true))
        model.emailText = "me@example.com"

        model.saveEmail()

        #expect(model.emailErrorMessage == "Couldn't save the email in the Keychain.")
        #expect(model.emailText == "me@example.com")
        #expect(!model.hasStoredEmail)
    }

    @Test func `a failed email removal explains itself`() {
        let model = model(FakeContactEmail("me@example.com", failsToSave: true))

        model.removeEmail()

        #expect(model.emailErrorMessage == "Couldn't remove the email from the Keychain.")
        #expect(model.hasStoredEmail)
    }

    private func settings(_ credentials: FakeCredentials) -> SettingsModel {
        SettingsModel(credentials: credentials, contactEmails: FakeContactEmail())
    }

    private func model(_ emails: FakeContactEmail = FakeContactEmail()) -> SettingsModel {
        SettingsModel(credentials: FakeCredentials(), contactEmails: emails)
    }
}
