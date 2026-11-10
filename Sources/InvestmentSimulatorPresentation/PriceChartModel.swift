import Foundation
import InvestmentSimulatorCore
import Observation

/// One ticker's price history chart: the range shown, its state, and each
/// range's closes once loaded. Research's chart and a stock card's Chart pane
/// (PIN-515) both use it.
@Observable
public final class PriceChartModel {
    public enum State: Equatable {
        case loading
        /// Oldest first.
        case loaded([ChartPoint])
        case empty
        case failed(QuoteError)
    }

    public let ticker: Ticker
    public private(set) var range = PriceRange.sixMonths
    public private(set) var state = State.loading

    private let dailyPrices: any DailyPriceProviding
    private let clock: () -> Date
    /// Each range's points once loaded, so going back to it asks for nothing.
    private var charts: [PriceRange: [ChartPoint]] = [:]

    public init(ticker: Ticker, dailyPrices: any DailyPriceProviding, clock: @escaping () -> Date) {
        self.ticker = ticker
        self.dailyPrices = dailyPrices
        self.clock = clock
    }

    /// Forgets the ranges loaded before, so the next `showRange` asks again.
    public func forgetRanges() {
        charts = [:]
    }

    /// Charts `range`, from memory if it was loaded before. A request
    /// cancelled before it starts changes nothing; one cancelled or
    /// superseded while loading changes nothing more.
    public func showRange(_ range: PriceRange) async {
        guard !Task.isCancelled else {
            return
        }
        self.range = range
        if let points = charts[range] {
            show(points)
            return
        }
        state = .loading
        let sessions = range.sessions(endingAt: clock())
        let bars: [DailyBar]
        do throws(QuoteError) {
            bars = try await dailyPrices.dailyBars(
                for: ticker,
                from: sessions.lowerBound,
                through: sessions.upperBound,
                interval: range.interval,
            )
        } catch .unknownTicker {
            // The ticker is known (Research's quote validated it, a card's
            // was traded), so here a 404 means no history: an empty state,
            // not an error (ADR-0019).
            bars = []
        } catch {
            // A newer request may have charted this range already.
            guard !Task.isCancelled, self.range == range, charts[range] == nil else {
                return
            }
            state = .failed(error)
            return
        }
        guard !Task.isCancelled else {
            return
        }
        let points = bars.sorted { $0.sessionDate < $1.sessionDate }.map { ChartPoint(bar: $0) }
        charts[range] = points
        if self.range == range {
            show(points)
        }
    }

    private func show(_ points: [ChartPoint]) {
        state = points.isEmpty ? .empty : .loaded(points)
    }
}
