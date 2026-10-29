import Foundation
import InvestmentSimulatorCore
import Observation

/// Drives the app-wide Research window (ADR-0019): the open tickers, in the
/// order opened, and the selected one. It outlives the window, so it owns
/// each ticker's quote task rather than a view's `.task`.
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
    private var tasks: [Ticker: Task<Void, Never>] = [:]

    public init(quotes: any QuoteProviding) {
        self.quotes = quotes
    }

    private var ticker: Ticker? {
        try? Ticker(symbolText)
    }

    public var symbolMessage: String? {
        symbolText.isEmpty || ticker != nil ? nil : "Enter a ticker symbol, such as VTI."
    }

    public var canOpen: Bool {
        ticker != nil
    }

    public var selectedTab: ResearchTabModel? {
        tabs.first { $0.ticker == selection }
    }

    /// Opens the typed ticker and selects it, or selects it if it's already
    /// open. Returns the new ticker's quote task. An unknown ticker is
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
        let tab = ResearchTabModel(ticker: ticker, quotes: quotes)
        tabs.append(tab)
        selection = ticker
        let task = Task {
            await tab.refresh()
            guard !Task.isCancelled, case .failed(.unknownTicker) = tab.quoteState else {
                return
            }
            drop(ticker, reselecting: previous)
            openError = .unknownTicker(ticker)
        }
        tasks[ticker] = task
        return task
    }

    /// Quotes an open ticker again, replacing any quote still running.
    @discardableResult
    public func refresh(_ ticker: Ticker) -> Task<Void, Never>? {
        guard let tab = tabs.first(where: { $0.ticker == ticker }) else {
            return nil
        }
        tasks[ticker]?.cancel()
        let task = Task { await tab.refresh() }
        tasks[ticker] = task
        return task
    }

    /// Closes `ticker`, cancelling its quote. If it was selected, the next
    /// ticker is selected, or the previous one at the end of the list.
    public func close(_ ticker: Ticker) {
        guard let index = tabs.firstIndex(where: { $0.ticker == ticker }) else {
            return
        }
        tasks.removeValue(forKey: ticker)?.cancel()
        tabs.remove(at: index)
        if selection == ticker {
            selection = tabs.indices.contains(index) ? tabs[index].ticker : tabs.last?.ticker
        }
    }

    private func drop(_ ticker: Ticker, reselecting previous: Ticker?) {
        tasks[ticker] = nil
        tabs.removeAll { $0.ticker == ticker }
        if selection == ticker {
            selection = tabs.contains { $0.ticker == previous } ? previous : tabs.last?.ticker
        }
    }
}
