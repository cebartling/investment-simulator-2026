import InvestmentSimulatorPresentation
import SwiftUI

/// Collects the starting cash balance for a new experiment.
struct NewExperimentSheet: View {
    @Bindable var model: NewExperimentModel
    let onCreate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Experiment")
                .font(.title2.bold())
            Form {
                TextField("Cash balance", value: $model.cashBalance, format: .currency(code: "USD"))
                if let message = model.validationMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: onCreate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCreate)
            }
        }
        .padding(20)
        .frame(width: 360)
        // Escape goes through Cancel, so the sheet never closes without a choice.
        .interactiveDismissDisabled()
    }
}
