import Foundation
import InvestmentSimulatorCore
import Observation

/// Drives the app-wide Research window (ADR-0019): the open tickers, in the
/// order opened, and the selected one. It outlives the window, so it owns
/// each ticker's load, chart range and section retry tasks rather than a
/// view's `.task`.
@Observable
public final class ResearchWindowModel {
    public var symbolText = "" {
        didSet {
            if symbolText != oldValue {
                openError = nil
            }
        }
    }

    public var selection: Ticker?
    public private(set) var tabs: [ResearchTabModel] = []
    /// Why the last ticker opened was dropped: its quote found no such ticker.
    public private(set) var openError: QuoteError?

    private let quotes: any QuoteProviding
    private let dailyPrices: any DailyPriceProviding
    private let ports: ResearchSectionPorts
    private let clock: () -> Date
    private var tasks: [Ticker: Task<Void, Never>] = [:]
    /// Each ticker's chart range still loading, apart from its first load.
    private var chartTasks: [Ticker: Task<Void, Never>] = [:]
    /// Each ticker's section retries still loading.
    private var retryTasks: [Ticker: [ResearchTabModel.Section: Task<Void, Never>]] = [:]

    /// `clock` tells the time chart ranges and trailing dividends reach back
    /// from.
    public init(
        quotes: any QuoteProviding,
        dailyPrices: any DailyPriceProviding,
        ports: ResearchSectionPorts,
        clock: @escaping () -> Date = Date.init,
    ) {
        self.quotes = quotes
        self.dailyPrices = dailyPrices
        self.ports = ports
        self.clock = clock
    }

    private var ticker: Ticker? {
        try? Ticker(symbolText)
    }

    public var symbolMessage: String? {
        symbolText.isEmpty || ticker != nil ? nil : "Enter a ticker symbol, such as VTI."
    }

    public var selectedTab: ResearchTabModel? {
        tabs.first { $0.ticker == selection }
    }

    /// Opens the typed ticker and selects it, or selects it if it's already
    /// open. Returns the new ticker's load task. An unknown ticker is
    /// dropped again once its quote says so.
    @discardableResult
    public func open() -> Task<Void, Never>? {
        guard let ticker else {
            return nil
        }
        symbolText = ""
        guard !tabs.contains(where: { $0.ticker == ticker }) else {
            selection = ticker
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
        return load(tab, reselecting: previous)
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
        chartTasks[ticker]?.cancel()
        let task = Task { await tab.showRange(range) }
        chartTasks[ticker] = task
        return task
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
        cancelTasks(of: ticker)
        tabs.remove(at: index)
        if selection == ticker {
            selection = tabs.indices.contains(index) ? tabs[index].ticker : tabs.last?.ticker
        }
    }

    /// Loads `tab`, cancelling anything still loading for it. If its quote
    /// finds no such ticker, the tab is dropped and `openError` says why.
    private func load(_ tab: ResearchTabModel, reselecting previous: Ticker?) -> Task<Void, Never> {
        let ticker = tab.ticker
        cancelTasks(of: ticker)
        let task = Task {
            await tab.load()
            guard !Task.isCancelled, case .failed(.unknownTicker) = tab.quoteState else {
                return
            }
            drop(ticker, reselecting: previous)
            openError = .unknownTicker(ticker)
        }
        tasks[ticker] = task
        return task
    }

    private func cancelTasks(of ticker: Ticker) {
        tasks.removeValue(forKey: ticker)?.cancel()
        cancelPartialTasks(of: ticker)
    }

    /// Cancels what loads one part of a ticker, apart from its full load.
    private func cancelPartialTasks(of ticker: Ticker) {
        chartTasks.removeValue(forKey: ticker)?.cancel()
        retryTasks.removeValue(forKey: ticker)?.values.forEach { $0.cancel() }
    }

    private func drop(_ ticker: Ticker, reselecting previous: Ticker?) {
        tasks[ticker] = nil
        cancelPartialTasks(of: ticker)
        tabs.removeAll { $0.ticker == ticker }
        if selection == ticker {
            selection = tabs.contains { $0.ticker == previous } ? previous : tabs.last?.ticker
        }
    }
}
