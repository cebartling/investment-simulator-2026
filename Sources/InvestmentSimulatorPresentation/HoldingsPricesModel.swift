import Foundation
import InvestmentSimulatorCore
import Observation

/// Quotes an experiment's tickers: the shares it holds, for the Experiment
/// header's Total Value and Gain/Loss (PIN-408) and the stock cards, plus
/// the tickers a stock card with no shares asks for (PIN-511). Keeps the
/// last good quote of each ticker, so a failed refresh falls back to it.
/// Nothing polls: the window prices new holdings, a card asks for its
/// ticker, and the user refreshes.
@Observable
public final class HoldingsPricesModel {
    public enum Valuation: Equatable {
        /// Every held ticker has a price. `pricesAsOf` is the earliest of
        /// their quotes, or nil with no holdings.
        case valued(totalValue: Money, gain: Gain, pricesAsOf: Date?)
        /// Some held ticker is still waiting for its first quote.
        case pricing
        /// Some held ticker has no price, because its quote failed.
        case unpriced(QuoteError)
    }

    /// True while Refresh Prices runs.
    public private(set) var isRefreshing = false

    /// How many quotes run at once.
    private static let maxConcurrentQuotes = 4

    private let quotes: any QuoteProviding
    private var lastGoodQuotes: [Ticker: Quote] = [:]
    private var failures: [Ticker: QuoteError] = [:]
    /// The tickers asked for on demand, which Refresh Prices quotes again
    /// whether or not they're held.
    private var tickersAskedFor: Set<Ticker> = []

    public init(quotes: any QuoteProviding) {
        self.quotes = quotes
    }

    /// The latest quote of `ticker` that answered, or nil before one has.
    public func lastGoodQuote(of ticker: Ticker) -> Quote? {
        lastGoodQuotes[ticker]
    }

    /// Why the latest quote of `ticker` failed, or nil when it answered or
    /// hasn't been asked for. A ticker can have both a failure and a last
    /// good quote, after a failed refresh.
    public func failure(of ticker: Ticker) -> QuoteError? {
        failures[ticker]
    }

    /// Quotes the tickers of `tickers` not answered yet, so new holdings get
    /// a price. A ticker whose quote failed waits for a refresh. A ticker
    /// still being quoted is quoted again: the window cancels a run when
    /// holdings change, and the cancelled run drops what it was quoting.
    public func priceNewHoldings(of tickers: Set<Ticker>) async {
        await quote(tickers.subtracting(answeredTickers))
    }

    /// Quotes `ticker` if it isn't answered yet, as `priceNewHoldings(of:)`
    /// does, and has Refresh Prices quote it from now on. For a stock card
    /// with no shares held, which the holdings don't price.
    public func priceOnDemand(_ ticker: Ticker) async {
        tickersAskedFor.insert(ticker)
        await quote(Set([ticker]).subtracting(answeredTickers))
    }

    /// Quotes again every ticker of `heldTickers` and every ticker asked for
    /// on demand, quoted or failed.
    public func refreshPrices(holding heldTickers: Set<Ticker>) async {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        await quote(heldTickers.union(tickersAskedFor))
    }

    /// True when `refreshPrices(holding:)` has something to quote and isn't
    /// already running.
    public func canRefresh(holding heldTickers: Set<Ticker>) -> Bool {
        !isRefreshing && !heldTickers.union(tickersAskedFor).isEmpty
    }

    public func valuation(of experiment: Experiment) -> Valuation {
        let held = experiment.heldTickers
        let prices = lastGoodQuotes.filter { held.contains($0.key) }.mapValues(\.price)
        if let totalValue = experiment.totalValue(prices: prices), let gain = experiment.gain(prices: prices) {
            let asOf = held.compactMap { lastGoodQuotes[$0]?.asOf }.min()
            return .valued(totalValue: totalValue, gain: gain, pricesAsOf: asOf)
        }
        let unpriced = held.filter { lastGoodQuotes[$0] == nil }.sorted { $0.symbol < $1.symbol }
        if let failure = unpriced.lazy.compactMap({ self.failures[$0] }).first {
            return .unpriced(failure)
        }
        return .pricing
    }

    /// The tickers with a quote or a failure.
    private var answeredTickers: Set<Ticker> {
        Set(lastGoodQuotes.keys).union(failures.keys)
    }

    /// Quotes `tickers`, at most `maxConcurrentQuotes` at once. Once
    /// cancelled it starts no more quotes and drops failures, which may
    /// only be the cancellation, leaving those tickers unanswered.
    private func quote(_ tickers: Set<Ticker>) async {
        guard !tickers.isEmpty else {
            return
        }
        let quotes = quotes
        await withTaskGroup(of: (Ticker, Result<Quote, QuoteError>).self) { group in
            var remaining = tickers.sorted { $0.symbol < $1.symbol }.makeIterator()
            for _ in 0 ..< Self.maxConcurrentQuotes {
                guard let ticker = remaining.next() else {
                    break
                }
                group.addTask { await Self.answer(for: ticker, from: quotes) }
            }
            for await (ticker, result) in group {
                record(result, for: ticker)
                if !Task.isCancelled, let next = remaining.next() {
                    group.addTask { await Self.answer(for: next, from: quotes) }
                }
            }
        }
    }

    private func record(_ result: Result<Quote, QuoteError>, for ticker: Ticker) {
        switch result {
        case let .success(quote):
            lastGoodQuotes[ticker] = quote
            failures[ticker] = nil
        case let .failure(error):
            guard !Task.isCancelled else {
                return
            }
            failures[ticker] = error
        }
    }

    private nonisolated static func answer(
        for ticker: Ticker,
        from quotes: any QuoteProviding,
    ) async -> (Ticker, Result<Quote, QuoteError>) {
        do throws(QuoteError) {
            return try await (ticker, .success(quotes.quote(for: ticker)))
        } catch {
            return (ticker, .failure(error))
        }
    }
}
