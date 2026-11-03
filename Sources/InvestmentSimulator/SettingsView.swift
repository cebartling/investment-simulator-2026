import InvestmentSimulatorPresentation
import SwiftUI

/// The Settings window (⌘,): the Equibles API key used to price purchases,
/// and the contact email SEC EDGAR asks for.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    private static let maskedKey = String(repeating: "•", count: 16)
    private static let apiKeysPage = URL(string: "https://www.equibles.com/dashboard/apikeys")!

    private var emailStatus: String {
        if model.isLoadingEmail {
            return "Reading Keychain…"
        }
        if model.isSavingEmail {
            return "Updating Keychain…"
        }
        return model.hasStoredEmail ? "Email saved" : "No email"
    }

    private var emailBusy: Bool {
        model.isLoadingEmail || model.isSavingEmail
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: model.hasStoredKey ? "API key saved" : "No API key")
                // The key is never read back; dots stand in for it while one is stored.
                SecureField("API key", text: $model.keyText, prompt: Text(model.hasStoredKey ? Self.maskedKey : "eq_…"))
                    .onSubmit { Task { await model.save() } }
                    .disabled(model.isSavingKey)
                HStack {
                    Button("Save Key") { Task { await model.save() } }
                        .disabled(!model.canSave || model.isSavingKey)
                    Button("Remove Key", role: .destructive) { Task { await model.removeKey() } }
                        .disabled(!model.hasStoredKey || model.isSavingKey)
                }
                if let message = model.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Equibles")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Purchases are priced by Equibles. The key is stored in your Keychain.")
                        .foregroundStyle(.secondary)
                    Link("Get an Equibles API key", destination: Self.apiKeysPage)
                }
            }
            Section {
                LabeledContent("Status", value: emailStatus)
                TextField("Email", text: $model.emailText, prompt: Text("you@example.com"))
                    .onSubmit { Task { await model.saveEmail() } }
                    .disabled(emailBusy)
                HStack {
                    Button("Save Email") { Task { await model.saveEmail() } }
                        .disabled(!model.canSaveEmail || emailBusy)
                    Button("Remove Email", role: .destructive) { Task { await model.removeEmail() } }
                        .disabled(!model.hasStoredEmail || emailBusy)
                }
                if let message = model.emailMessage ?? model.emailErrorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("SEC EDGAR")
            } footer: {
                Text("""
                SEC asks for a contact email with each request. Research's company search and \
                exchange names need it. The email is stored in your Keychain.
                """)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await model.loadStoredEmail() }
        // A grouped form fills its window; size the window to the content.
        .frame(width: 460, height: 520)
    }
}
