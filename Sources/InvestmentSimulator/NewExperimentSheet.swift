import InvestmentSimulatorPresentation
import SwiftUI

/// Collects the starting cash balance for a new experiment.
struct NewExperimentSheet: View {
    @Bindable var model: NewExperimentModel
    let onCreate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        // The grouped form insets its section by 20 points, so only the title
        // and buttons carry their own padding, to line up with its edges.
        VStack(alignment: .leading, spacing: 0) {
            Text("New Experiment")
                .font(.title2.bold())
                .padding([.horizontal, .top], 20)
            Form {
                TextField("Cash balance", value: $model.cashBalance, format: .currency(code: "USD"))
                if let message = model.validationMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: onCreate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCreate)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 360)
        // Escape goes through Cancel, so the sheet never closes without a choice.
        .interactiveDismissDisabled()
    }
}
