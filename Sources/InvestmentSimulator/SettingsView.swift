import InvestmentSimulatorPresentation
import SwiftUI

/// The Settings window (⌘,): the Equibles API key used to price purchases,
/// and the contact email SEC EDGAR asks for.
struct SettingsView: View {
    @Bindable var model: SettingsModel
    @FocusState private var focusedField: Field?
    /// The field Return was pressed in, so focus can come back once its
    /// write ends and the disabled field has dropped it.
    @State private var fieldToRefocus: Field?

    private enum Field {
        case key
        case email
    }

    private static let maskedKey = String(repeating: "•", count: 16)
    private static let apiKeysPage = URL(string: "https://www.equibles.com/dashboard/apikeys")!

    private var keyStatus: String {
        if model.isSavingKey {
            return "Updating Keychain…"
        }
        return model.hasStoredKey ? "API key saved" : "No API key"
    }

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

    /// Puts focus back in `field` when its write ends, if Return started it.
    private func restoreFocus(to field: Field, whenBusy busy: Bool) {
        guard !busy, fieldToRefocus == field else {
            return
        }
        fieldToRefocus = nil
        focusedField = field
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: keyStatus)
                // The key is never read back; dots stand in for it while one is stored.
                SecureField("API key", text: $model.keyText, prompt: Text(model.hasStoredKey ? Self.maskedKey : "eq_…"))
                    .focused($focusedField, equals: .key)
                    .onSubmit {
                        fieldToRefocus = .key
                        Task { await model.save() }
                    }
                    .disabled(model.isSavingKey)
                    .onChange(of: model.isSavingKey) { restoreFocus(to: .key, whenBusy: model.isSavingKey) }
                HStack {
                    Button("Save Key") { Task { await model.save() } }
                        .disabled(!model.canSave)
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
                    .focused($focusedField, equals: .email)
                    .onSubmit {
                        fieldToRefocus = .email
                        Task { await model.saveEmail() }
                    }
                    .disabled(emailBusy)
                    .onChange(of: emailBusy) { restoreFocus(to: .email, whenBusy: emailBusy) }
                HStack {
                    Button("Save Email") { Task { await model.saveEmail() } }
                        .disabled(!model.canSaveEmail || model.isLoadingEmail)
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
