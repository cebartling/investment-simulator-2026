import SwiftUI

/// Shown instead of the library when the database can't be opened or
/// brought to the current schema (ADR-0021). The app doesn't go on with an
/// empty store.
struct DatabaseErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Can't Open the Experiment Database", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
                .textSelection(.enabled)
        } actions: {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
