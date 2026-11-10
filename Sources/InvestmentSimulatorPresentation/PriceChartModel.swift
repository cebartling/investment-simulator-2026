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

/// One bar's close and the session day it belongs to. It holds no time zone,
/// so a cached range stays right when the Mac's zone changes; `plot` places it
/// on the chart's axis in the zone the view names.
public nonisolated struct ChartPoint: Equatable, Sendable {
    public let sessionDate: String
    public let close: Decimal

    public init(bar: DailyBar) {
        self.init(sessionDate: bar.sessionDate, close: bar.close)
    }

    public init(sessionDate: String, close: Decimal) {
        self.sessionDate = sessionDate
        self.close = close
    }

    /// A close at its place on a chart axis.
    public struct Plotted: Equatable, Sendable {
        public let date: Date
        public let close: Decimal
    }

    /// Places each close at noon of its session's day in `timeZone`, which
    /// must be the zone the chart axis uses, so the axis shows the session's
    /// own day and no daylight saving change moves it to another day. A point
    /// whose session date isn't a real date is left out.
    public static func plot(_ points: [ChartPoint], in timeZone: TimeZone) -> [Plotted] {
        let parser = SessionDateParser(timeZone: timeZone)
        return points.compactMap { point in
            parser.date(of: point.sessionDate, hour: 12).map { Plotted(date: $0, close: point.close) }
        }
    }
}
