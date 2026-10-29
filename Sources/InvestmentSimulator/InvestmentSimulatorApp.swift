import AppKit
import InvestmentSimulatorCore
import InvestmentSimulatorMarketData
import InvestmentSimulatorPresentation
import SwiftUI

/// The app-wide composition root: services built once here are passed to
/// each window through its initializer (ADR-0011, ADR-0012).
@main
struct InvestmentSimulatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let quotes: any QuoteProviding
    private let dailyPrices: any DailyPriceProviding
    @State private var settings: SettingsModel
    /// App-wide, so open tickers survive closing the Research window (ADR-0019).
    @State private var research: ResearchWindowModel

    init() {
        let credentials = KeychainCredentialStore()
        let equibles = EquiblesQuoteProvider(transport: URLSessionTransport(), credentials: credentials)
        quotes = equibles
        dailyPrices = equibles
        _settings = State(initialValue: SettingsModel(credentials: credentials))
        _research = State(initialValue: ResearchWindowModel(quotes: equibles))
    }

    var body: some Scene {
        DocumentGroup(newDocument: ExperimentDocument()) { file in
            // Read here, so the title follows Save As.
            MainWindow(document: file.$document, fileURL: file.fileURL, quotes: quotes, dailyPrices: dailyPrices)
        }
        // The scene puts itself in the Window menu with its shortcut.
        Window("Research", id: "research") {
            ResearchWindow(model: research)
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        Settings {
            SettingsView(model: settings)
        }
    }
}

/// Composition root for one document window (ADR-0011). `@State` on the
/// `App` would be shared by every window; here each window gets its own
/// model, seeded from its document. Changes flow both ways.
struct MainWindow: View {
    @Binding var document: ExperimentDocument
    /// The document's file, or nil until it is saved.
    let fileURL: URL?
    @State private var model: MainWindowModel

    init(
        document: Binding<ExperimentDocument>,
        fileURL: URL?,
        quotes: any QuoteProviding,
        dailyPrices: any DailyPriceProviding,
    ) {
        _document = document
        self.fileURL = fileURL
        _model = State(initialValue: MainWindowModel(
            experiment: document.wrappedValue.experiment,
            needsSetup: document.wrappedValue.needsSetup,
            quotes: quotes,
            dailyPrices: dailyPrices,
        ))
    }

    var body: some View {
        // Writing on create, not on a change in value, marks even a $0
        // experiment (equal to the new document's) as edited.
        ContentView(
            model: model,
            fileURL: fileURL,
            onCreate: {
                if let created = model.createExperiment() {
                    document.experiment = created
                }
            },
            onPurchase: {
                if let updated = model.completePurchase() {
                    document.experiment = updated
                }
            },
            onSell: {
                if let updated = model.completeSale() {
                    document.experiment = updated
                }
            },
            onPlaceLimitOrder: {
                if let updated = model.completeLimitOrder() {
                    document.experiment = updated
                }
            },
            onPlaceBuyLimitOrder: {
                if let updated = model.completeBuyLimitOrder() {
                    document.experiment = updated
                }
            },
            onCancelOrder: { id in
                if let updated = model.cancelOrder(id: id) {
                    document.experiment = updated
                }
            },
            onCheckOrders: {
                if let updated = await model.checkLimitOrders() {
                    document.experiment = updated
                }
            },
            onSaveDetails: {
                if let updated = model.completeEditingDetails() {
                    document.experiment = updated
                }
            },
        )
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
