import InvestmentSimulatorPresentation
import Testing

/// A Keychain write can wait on an access prompt, so none may run on the main
/// thread, and the controls show it while they wait (PIN-489).
extension SettingsKeychainTests {
    @MainActor
    struct Writes {
        // MARK: Email

        @Test func `saving the email writes off the main thread`() async {
            let emails = FakeContactEmail()
            let model = model(emails: emails)
            model.emailText = "me@example.com"

            await model.saveEmail()

            #expect(emails.writeCount == 1)
            #expect(!emails.wroteOnMainThread)
            #expect(model.hasStoredEmail)
        }

        @Test func `removing the email writes off the main thread`() async {
            let emails = FakeContactEmail("me@example.com")
            let model = model(emails: emails)

            await model.removeEmail()

            #expect(emails.writeCount == 1)
            #expect(!emails.wroteOnMainThread)
            #expect(!model.hasStoredEmail)
        }

        @Test func `the email shows as saving until the write finishes`() async {
            let emails = FakeContactEmail(writeGated: true)
            let model = model(emails: emails)
            model.emailText = "me@example.com"
            #expect(!model.isSavingEmail)

            let save = Task { await model.saveEmail() }
            while !model.isSavingEmail {
                await Task.yield()
            }
            #expect(!model.hasStoredEmail)
            emails.releaseWrite()
            await save.value

            #expect(!model.isSavingEmail)
            #expect(model.hasStoredEmail)
        }

        @Test func `a failed email save stops showing as saving and keeps the field`() async {
            let model = model(emails: FakeContactEmail(failsToSave: true))
            model.emailText = "me@example.com"

            await model.saveEmail()

            #expect(!model.isSavingEmail)
            #expect(model.emailText == "me@example.com")
            #expect(model.emailErrorMessage == "Couldn't save the email in the Keychain.")
        }

        @Test func `a second email save while one is running doesn't write again`() async {
            let emails = FakeContactEmail(writeGated: true)
            let model = model(emails: emails)
            model.emailText = "me@example.com"

            let first = Task { await model.saveEmail() }
            while !model.isSavingEmail {
                await Task.yield()
            }
            let second = Task { await model.saveEmail() }
            await second.value
            emails.releaseWrite()
            await first.value

            #expect(emails.writeCount == 1)
        }

        // MARK: API key

        @Test func `saving the key writes off the main thread`() async {
            let credentials = FakeCredentials()
            let model = model(credentials: credentials)
            model.keyText = "eq_new"

            await model.save()

            #expect(credentials.writeCount == 1)
            #expect(!credentials.wroteOnMainThread)
            #expect(model.hasStoredKey)
            #expect(model.keyText.isEmpty)
        }

        @Test func `removing the key writes off the main thread`() async {
            let credentials = FakeCredentials("eq_old")
            let model = model(credentials: credentials)

            await model.removeKey()

            #expect(credentials.writeCount == 1)
            #expect(!credentials.wroteOnMainThread)
            #expect(!model.hasStoredKey)
        }

        @Test func `the key shows as saving until the write finishes`() async {
            let credentials = FakeCredentials(writeGated: true)
            let model = model(credentials: credentials)
            model.keyText = "eq_new"
            #expect(!model.isSavingKey)

            let save = Task { await model.save() }
            while !model.isSavingKey {
                await Task.yield()
            }
            #expect(!model.hasStoredKey)
            credentials.releaseWrite()
            await save.value

            #expect(!model.isSavingKey)
            #expect(model.hasStoredKey)
        }

        @Test func `a failed key save stops showing as saving and keeps the text`() async {
            let model = model(credentials: FakeCredentials(failsToSave: true))
            model.keyText = "eq_new"

            await model.save()

            #expect(!model.isSavingKey)
            #expect(model.keyText == "eq_new")
            #expect(model.errorMessage == "Couldn't save the API key in the Keychain.")
        }

        @Test func `a second key save while one is running doesn't write again`() async {
            let credentials = FakeCredentials(writeGated: true)
            let model = model(credentials: credentials)
            model.keyText = "eq_new"

            let first = Task { await model.save() }
            while !model.isSavingKey {
                await Task.yield()
            }
            let second = Task { await model.save() }
            await second.value
            credentials.releaseWrite()
            await first.value

            #expect(credentials.writeCount == 1)
        }

        private func model(
            credentials: FakeCredentials = FakeCredentials(),
            emails: FakeContactEmail = FakeContactEmail(),
        ) -> SettingsModel {
            SettingsModel(credentials: credentials, contactEmails: emails)
        }
    }
}
