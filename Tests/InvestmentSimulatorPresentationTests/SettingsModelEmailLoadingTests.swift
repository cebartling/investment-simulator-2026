import InvestmentSimulatorPresentation
import Testing

@MainActor
struct SettingsModelEmailLoadingTests {
    @Test func `loading reads the email off the main thread`() async {
        let emails = FakeContactEmail("me@example.com")
        let model = model(emails)

        await model.loadStoredEmail()

        #expect(emails.readCount == 1)
        #expect(!emails.readOnMainThread)
    }

    @Test func `the email shows as loading until the read finishes`() async {
        let emails = FakeContactEmail("me@example.com", gated: true)
        let model = model(emails)
        #expect(!model.isLoadingEmail)

        let load = Task { await model.loadStoredEmail() }
        while !model.isLoadingEmail {
            await Task.yield()
        }
        emails.releaseRead()
        await load.value

        #expect(!model.isLoadingEmail)
        #expect(model.emailText == "me@example.com")
    }

    @Test func `typing while the email loads is not overwritten`() async {
        let emails = FakeContactEmail("me@example.com", gated: true)
        let model = model(emails)

        let load = Task { await model.loadStoredEmail() }
        while !model.isLoadingEmail {
            await Task.yield()
        }
        model.emailText = "you@example.com"
        emails.releaseRead()
        await load.value

        #expect(model.emailText == "you@example.com")
    }

    @Test func `removing the email while it loads is not undone by the load`() async {
        let emails = FakeContactEmail("me@example.com", gated: true)
        let model = model(emails)

        let load = Task { await model.loadStoredEmail() }
        while !model.isLoadingEmail {
            await Task.yield()
        }
        await model.removeEmail()
        emails.releaseRead()
        await load.value

        #expect(model.emailText.isEmpty)
        #expect(!model.hasStoredEmail)
    }

    @Test func `a second load while one is running doesn't read again`() async {
        let emails = FakeContactEmail("me@example.com", gated: true)
        let model = model(emails)

        let load = Task { await model.loadStoredEmail() }
        while !model.isLoadingEmail {
            await Task.yield()
        }
        let second = Task { await model.loadStoredEmail() }
        await second.value
        emails.releaseRead()
        await load.value

        #expect(emails.readCount == 1)
    }

    @Test func `a failed load stops showing as loading`() async {
        let model = model(FakeContactEmail("me@example.com", failsToRead: true))

        await model.loadStoredEmail()

        #expect(!model.isLoadingEmail)
        #expect(model.emailErrorMessage != nil)
    }

    private func model(_ emails: FakeContactEmail) -> SettingsModel {
        SettingsModel(credentials: FakeCredentials(), contactEmails: emails)
    }
}
