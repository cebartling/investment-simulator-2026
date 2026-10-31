import InvestmentSimulatorPresentation
import SwiftUI

/// The Settings window (⌘,): the Equibles API key used to price purchases,
/// and the contact email SEC EDGAR asks for.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    private static let apiKeysPage = URL(string: "https://www.equibles.com/dashboard/apikeys")!

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: model.hasStoredKey ? "API key saved" : "No API key")
                SecureField("API key", text: $model.keyText, prompt: Text("eq_…"))
                    .onSubmit(model.save)
                HStack {
                    Button("Save Key", action: model.save)
                        .disabled(!model.canSave)
                    Button("Remove Key", role: .destructive, action: model.removeKey)
                        .disabled(!model.hasStoredKey)
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
                LabeledContent("Status", value: model.hasStoredEmail ? "Email saved" : "No email")
                TextField("Email", text: $model.emailText, prompt: Text("you@example.com"))
                    .onSubmit(model.saveEmail)
                HStack {
                    Button("Save Email", action: model.saveEmail)
                        .disabled(!model.canSaveEmail)
                    Button("Remove Email", role: .destructive, action: model.removeEmail)
                        .disabled(!model.hasStoredEmail)
                }
                if let message = model.emailMessage ?? model.emailErrorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("SEC EDGAR")
            } footer: {
                Text("SEC asks for a contact email with each request. Research's company search and exchange names need it. The email is stored in your Keychain.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // A grouped form fills its window; size the window to the content.
        .frame(width: 460, height: 520)
    }
}
