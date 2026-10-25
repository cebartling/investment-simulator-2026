import AppKit
import InvestmentSimulatorPresentation
import SwiftUI

@main
struct InvestmentSimulatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: ExperimentDocument()) { file in
            MainWindow(document: file.$document)
        }
    }
}

/// Composition root for one document window (ADR-0010). `@State` on the
/// `App` would be shared by every window; here each window gets its own
/// model, seeded from its document. Changes flow both ways.
struct MainWindow: View {
    @Binding var document: ExperimentDocument
    @State private var model: MainWindowModel

    init(document: Binding<ExperimentDocument>) {
        _document = document
        _model = State(initialValue: MainWindowModel(
            experiment: document.wrappedValue.experiment,
            needsSetup: document.wrappedValue.needsSetup,
        ))
    }

    var body: some View {
        // Writing on create, not on a change in value, marks even a $0
        // experiment (equal to the new document's) as edited.
        ContentView(model: model, onCreate: {
            if let created = model.createExperiment() {
                document.experiment = created
            }
        })
        // Changes the document makes itself, like File › Revert To.
        .onChange(of: document.experiment) { _, experiment in
            model.replaceExperiment(with: experiment)
        }
    }
}

/// A bare SwiftPM executable launched via `swift run` starts as a background
/// process with no Dock icon or key window; promote it to a regular app.
/// The policy must change before launch finishes, or the menu bar can stay
/// unresponsive until the user switches apps.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.activate()
    }
}
