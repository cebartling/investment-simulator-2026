import AppKit
import InvestmentSimulatorCore
import InvestmentSimulatorMarketData
import InvestmentSimulatorPersistence
import InvestmentSimulatorPresentation
import SwiftUI

/// The app-wide composition root: services built once here are passed to
/// the window through its initializer (ADR-0012, ADR-0021).
@main
struct InvestmentSimulatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let quotes: any QuoteProviding
    private let dailyPrices: any DailyPriceProviding
    @State private var settings: SettingsModel
    /// App-wide, so open tickers survive closing the Research window (ADR-0019).
    @State private var research: ResearchWindowModel
    /// Nil when the database couldn't be opened; `databaseError` says why.
    @State private var library: LibraryWindowModel?
    private let databaseError: String?

    init() {
        let credentials = KeychainCredentialStore()
        let contactEmails = KeychainContactEmailStore()
        let transport = URLSessionTransport()
        let equibles = EquiblesQuoteProvider(transport: transport, credentials: credentials)
        let researchData = EquiblesResearchProvider(transport: transport, credentials: credentials)
        // Ephemeral, so URLCache keeps neither the list nor the request naming
        // the email on disk (ADR-0019).
        let edgarTransport = URLSessionTransport(session: URLSession(configuration: .ephemeral))
        quotes = equibles
        dailyPrices = equibles
        do {
            let repository = try ExperimentDatabase.open(at: ExperimentDatabase.defaultURL())
            let library = LibraryModel(repository: repository)
            _library = State(initialValue: LibraryWindowModel(
                library: library,
                makeExperimentModel: { id in
                    MainWindowModel(id: id, repository: repository, quotes: equibles, dailyPrices: equibles)
                },
            ))
            databaseError = nil
        } catch {
            _library = State(initialValue: nil)
            databaseError = error.localizedDescription
        }
        _settings = State(initialValue: SettingsModel(credentials: credentials, contactEmails: contactEmails))
        _research = State(initialValue: ResearchWindowModel(
            quotes: quotes,
            dailyPrices: dailyPrices,
            ports: ResearchSectionPorts(
                profiles: researchData,
                multiples: researchData,
                dividends: researchData,
                pressReleases: researchData,
                filings: researchData,
                statements: researchData,
                directory: EdgarSecurityDirectory(transport: edgarTransport, contactEmails: contactEmails),
            ),
            tickerStore: UserDefaultsResearchTickerStore(),
        ))
    }

    var body: some Scene {
        Window("Investment Simulator", id: "library") {
            if let library {
                LibraryWindow(model: library, research: research)
            } else {
                DatabaseErrorView(message: databaseError ?? "Unknown error.")
            }
        }
        .commands {
            if let library {
                CommandGroup(replacing: .newItem) {
                    Button("New Experiment…", action: library.beginNewExperiment)
                        .keyboardShortcut("n")
                    Button("Research") { library.destination = .research }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                }
            }
        }
        Settings {
            SettingsView(model: settings)
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
