import Foundation
import InvestmentSimulatorCore
import Observation

/// Drives the app-wide Research window (ADR-0019): the open tickers, in the
/// order opened, and the selected one. It outlives the window, so it owns
/// each ticker's load, chart range, statement and section retry tasks rather
/// than a view's `.task`.
@Observable
public final class ResearchWindowModel {
    public var symbolText = "" {
        didSet {
            if symbolText != oldValue {
                openError = nil
                symbolRejected = false
            }
        }
    }

    public var selection: Ticker? {
        didSet {
            save()
        }
    }

    public private(set) var tabs: [ResearchTabModel] = [] {
        didSet {
            save()
        }
    }

    /// Why the last ticker opened was dropped: its quote found no such ticker.
    public private(set) var openError: QuoteError?
    /// The best matches for the field's text, once searched.
    public private(set) var searchResults: [ListedSecurity] = []
    public private(set) var searchMessage: String?

    /// The text `searchResults` answer, which lags the field while searching.
    private var resultsText = ""
    /// The field's text was entered, and it can't be a ticker. It may be a
    /// company name until then, so nothing is said while typing.
    private var symbolRejected = false
    private let quotes: any QuoteProviding
    private let dailyPrices: any DailyPriceProviding
    private let ports: ResearchSectionPorts
    private let tickerStore: any ResearchTickerStoring
    private let clock: () -> Date
    /// Nothing is saved until the saved tickers have been restored, so a model
    /// that opens a ticker first can't overwrite the last session's list.
    private var isRestored = false
    private var tasks: [Ticker: Task<Void, Never>] = [:]
    /// Each ticker's statement table still loading.
    private var statementTasks: [Ticker: Task<Void, Never>] = [:]
    /// Each ticker's section retries still loading.
    private var retryTasks: [Ticker: [ResearchTabModel.Section: Task<Void, Never>]] = [:]

    /// `tickerStore` keeps the open tickers between launches; `restore()` reads
    /// it. `clock` tells the time chart ranges and trailing dividends reach back
    /// from.
    public init(
        quotes: any QuoteProviding,
        dailyPrices: any DailyPriceProviding,
        ports: ResearchSectionPorts,
        tickerStore: any ResearchTickerStoring,
        clock: @escaping () -> Date = Date.init,
    ) {
        self.quotes = quotes
        self.dailyPrices = dailyPrices
        self.ports = ports
        self.tickerStore = tickerStore
        self.clock = clock
    }

    /// Reopens the saved tickers in order and selects the saved one, or the
    /// last. A symbol that is no longer valid is skipped, and one whose quote
    /// finds no such ticker is dropped quietly, as the user typed nothing.
    /// Does nothing after the first call. Returns each load.
    @discardableResult
    public func restore() -> [Task<Void, Never>] {
        guard !isRestored else {
            return []
        }
        let saved = tickerStore.load()
        let loads = saved.symbols.compactMap { symbol in
            (try? Ticker(symbol)).flatMap { open($0, typed: nil, restoring: true) }
        }
        isRestored = true
        selection = tabs.first { $0.ticker.symbol == saved.selected }?.ticker ?? tabs.last?.ticker
        return loads
    }

    private func save() {
        guard isRestored else {
            return
        }
        tickerStore.save(SavedResearchTickers(symbols: tabs.map(\.ticker.symbol), selected: selection?.symbol))
    }

    private var ticker: Ticker? {
        try? Ticker(symbolText)
    }

    private var searchText: String {
        symbolText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var symbolMessage: String? {
        symbolRejected ? "Enter a ticker symbol, such as VTI." : nil
    }

    public var selectedTab: ResearchTabModel? {
        tabs.first { $0.ticker == selection }
    }

    /// Finds the field's text in the directory. Results for text that has
    /// changed since are dropped. Without the contact email search is off,
    /// and typed tickers still open (ADR-0019).
    public func search() async {
        let text = searchText
        guard !text.isEmpty else {
            searchResults = []
            searchMessage = nil
            return
        }
        let results: [ListedSecurity]
        let message: String?
        do throws(MarketDataError) {
            results = try await ports.directory.search(text)
            message = nil
        } catch .missingContactEmail {
            results = []
            message = "Add your SEC contact email in Settings to search by company name."
        } catch {
            results = []
            message = error.localizedDescription
        }
        guard text == searchText else {
            return
        }
        searchResults = results
        resultsText = text
        searchMessage = message
        if !results.isEmpty {
            symbolRejected = false
        }
    }

    /// Opens the top match when the text matches only company names, and
    /// otherwise exactly what was typed: the text may be a ticker the
    /// directory lacks, which must not become another security.
    @discardableResult
    public func open() -> Task<Void, Never>? {
        if resultsText == searchText, let match = searchResults.topNameMatch(for: searchText) {
            return open(match.ticker, typed: symbolText)
        }
        guard let ticker else {
            symbolRejected = !searchText.isEmpty
            return nil
        }
        return open(ticker, typed: symbolText)
    }

    /// Opens `ticker` and selects it, or selects its tab if it's already
    /// open, however its share class is spelled there.
    /// Returns the new ticker's load task. An unknown ticker is dropped again
    /// once its quote says so.
    @discardableResult
    public func open(_ ticker: Ticker) -> Task<Void, Never>? {
        open(ticker, typed: nil)
    }

    private func open(_ ticker: Ticker, typed: String?, restoring: Bool = false) -> Task<Void, Never>? {
        symbolText = ""
        searchResults = []
        searchMessage = nil
        if let open = tabs.first(where: { $0.ticker.isSameSecurity(as: ticker) }) {
            selection = open.ticker
            return nil
        }
        let previous = selection
        let tab = ResearchTabModel(
            ticker: ticker,
            quotes: quotes,
            dailyPrices: dailyPrices,
            ports: ports,
            clock: clock,
        )
        tabs.append(tab)
        selection = ticker
        return load(tab, reselecting: previous, restoring: typed, reportsUnknown: !restoring)
    }

    /// Loads an open ticker's quote, chart and sections again, replacing
    /// anything still loading for it. As when opening, an unknown ticker is
    /// dropped.
    @discardableResult
    public func refresh(_ ticker: Ticker) -> Task<Void, Never>? {
        guard let tab = tabs.first(where: { $0.ticker == ticker }) else {
            return nil
        }
        return load(tab, reselecting: nil)
    }

    /// Charts `range` for an open ticker, replacing a range still loading.
    @discardableResult
    public func showRange(_ range: PriceRange, for ticker: Ticker) -> Task<Void, Never>? {
        guard let tab = tabs.first(where: { $0.ticker == ticker }) else {
            return nil
        }
        return tab.chart.load(range)
    }

    /// Shows a statement for an open ticker, replacing one still loading.
    @discardableResult
    public func showStatements(_ selection: StatementSelection, for ticker: Ticker) -> Task<Void, Never>? {
        guard let tab = tabs.first(where: { $0.ticker == ticker }) else {
            return nil
        }
        statementTasks[ticker]?.cancel()
        let task = Task { await tab.showStatements(selection) }
        statementTasks[ticker] = task
        return task
    }

    /// Shows a pane of an open ticker. Entering Financials loads the
    /// statement shown, if it hasn't loaded; leaving it cancels a load still
    /// running and keeps the tables loaded. Selecting the pane already shown
    /// does nothing, so a load under way isn't restarted. The task is nil
    /// unless a load started.
    @discardableResult
    public func selectPane(_ pane: ResearchPane, for ticker: Ticker) -> Task<Void, Never>? {
        guard let tab = tabs.first(where: { $0.ticker == ticker }), tab.selectedPane != pane else {
            return nil
        }
        tab.selectedPane = pane
        guard pane == .financials else {
            statementTasks.removeValue(forKey: ticker)?.cancel()
            return nil
        }
        return showStatements(tab.statementSelection, for: ticker)
    }

    /// Loads one section of an open ticker again, leaving what has already
    /// loaded as it is, and replacing a retry of that section still loading.
    @discardableResult
    public func retry(_ section: ResearchTabModel.Section, for ticker: Ticker) -> Task<Void, Never>? {
        guard let tab = tabs.first(where: { $0.ticker == ticker }) else {
            return nil
        }
        retryTasks[ticker]?[section]?.cancel()
        let task = Task { await tab.load(section) }
        retryTasks[ticker, default: [:]][section] = task
        return task
    }

    /// Closes `ticker`, cancelling all it was loading. If it was selected, the next
    /// ticker is selected, or the previous one at the end of the list.
    public func close(_ ticker: Ticker) {
        guard let index = tabs.firstIndex(where: { $0.ticker == ticker }) else {
            return
        }
        cancelTasks(of: tabs[index])
        tabs.remove(at: index)
        if selection == ticker {
            selection = tabs.indices.contains(index) ? tabs[index].ticker : tabs.last?.ticker
        }
    }

    /// Loads `tab`, cancelling anything still loading for it. If its quote
    /// finds no such ticker, the tab is dropped and `openError` says why.
    /// The `typed` text returns to an empty field, as it may have been a
    /// company name, which brings back its matches or the search message.
    private func load(
        _ tab: ResearchTabModel,
        reselecting previous: Ticker?,
        restoring typed: String? = nil,
        reportsUnknown: Bool = true,
    ) -> Task<Void, Never> {
        let ticker = tab.ticker
        cancelTasks(of: tab)
        tab.forgetStatements()
        if tab.selectedPane == .financials {
            showStatements(tab.statementSelection, for: ticker)
        }
        let task = Task {
            await tab.load()
            guard !Task.isCancelled, case .failed(.unknownTicker) = tab.quoteState else {
                return
            }
            drop(tab, reselecting: previous)
            if let typed, symbolText.isEmpty {
                symbolText = typed
            }
            if reportsUnknown {
                openError = .unknownTicker(ticker)
            }
        }
        tasks[ticker] = task
        return task
    }

    private func cancelTasks(of tab: ResearchTabModel) {
        tasks.removeValue(forKey: tab.ticker)?.cancel()
        cancelPartialTasks(of: tab)
    }

    /// Cancels what loads one part of a ticker, apart from its full load.
    private func cancelPartialTasks(of tab: ResearchTabModel) {
        tab.chart.cancelLoad()
        statementTasks.removeValue(forKey: tab.ticker)?.cancel()
        retryTasks.removeValue(forKey: tab.ticker)?.values.forEach { $0.cancel() }
    }

    private func drop(_ tab: ResearchTabModel, reselecting previous: Ticker?) {
        let ticker = tab.ticker
        tasks[ticker] = nil
        cancelPartialTasks(of: tab)
        tabs.removeAll { $0.ticker == ticker }
        if selection == ticker {
            selection = tabs.contains { $0.ticker == previous } ? previous : tabs.last?.ticker
        }
    }
}
