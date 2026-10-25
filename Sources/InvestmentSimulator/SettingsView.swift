import InvestmentSimulatorPresentation
import SwiftUI

/// The Settings window (⌘,): the Equibles API key used to price purchases.
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
        }
        .formStyle(.grouped)
        // A grouped form fills its window; size the window to the content.
        .frame(width: 460, height: 260)
    }
}
