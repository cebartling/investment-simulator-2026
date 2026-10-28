import InvestmentSimulatorPresentation
import SwiftUI

/// Edits the experiment's name and notes.
struct ExperimentDetailsSheet: View {
    @Bindable var model: ExperimentDetailsModel
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        // The grouped form insets its section by 20 points, so only the title
        // and buttons carry their own padding, to line up with its edges.
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit Details")
                .font(.title2.bold())
                .padding([.horizontal, .top], 20)
            Form {
                TextField("Name", text: $model.name, prompt: Text("Uses the file's name"))
                TextField("Notes", text: $model.notes, axis: .vertical)
                    .lineLimit(3 ... 6)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 420)
        .interactiveDismissDisabled()
    }
}
