import Foundation
import InvestmentSimulatorCore
import Observation

/// One ticker's price history chart: the range shown, its state, each range's
/// closes once loaded, and the range still loading (PIN-523). Research's chart
/// and a stock card's Chart pane (PIN-515) both use it.
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
    /// The sessions the bars `state` holds were asked for, nil while loading
    /// or failed. They end on the day the bars loaded, which may be before
    /// today (PIN-520), and stay until new bars replace them, even once
    /// `forgetRanges()` has the next `showRange` ask again.
    public private(set) var shownSessions: ClosedRange<String>?

    private let dailyPrices: any DailyPriceProviding
    private let clock: () -> Date
    /// Each range once loaded, so going back to it asks for nothing.
    private var charts: [PriceRange: Loaded] = [:]
    /// The range `load(_:)` started last, so a newer one replaces it. A
    /// `showRange` awaited directly, as Research's first load, isn't kept.
    /// Not observed: no view reads it (PIN-522).
    @ObservationIgnored private var loading: Task<Void, Never>?

    /// A range's closes and the sessions they were asked for.
    private struct Loaded {
        let sessions: ClosedRange<String>
        let points: [ChartPoint]
    }

    public init(ticker: Ticker, dailyPrices: any DailyPriceProviding, clock: @escaping () -> Date) {
        self.ticker = ticker
        self.dailyPrices = dailyPrices
        self.clock = clock
    }

    /// Forgets the ranges loaded before, so the next `showRange` asks again.
    public func forgetRanges() {
        charts = [:]
    }

    /// Charts `range` in a task of its own, cancelling the range still loading.
    @discardableResult
    public func load(_ range: PriceRange) -> Task<Void, Never> {
        loading?.cancel()
        let task = Task { await showRange(range) }
        loading = task
        return task
    }

    /// The task still loading the range shown, nil once it loaded, failed or
    /// was cancelled, so showing the chart again while it loads asks once.
    public var loadInProgress: Task<Void, Never>? {
        state == .loading ? loading : nil
    }

    /// Cancels the range still loading. The chart keeps what it shows.
    public func cancelLoad() {
        loading?.cancel()
        loading = nil
    }

    /// Charts `range`, from memory if it was loaded before. A request
    /// cancelled before it starts changes nothing; one cancelled or
    /// superseded while loading changes nothing more.
    public func showRange(_ range: PriceRange) async {
        guard !Task.isCancelled else {
            return
        }
        self.range = range
        if let loaded = charts[range] {
            show(loaded)
            return
        }
        state = .loading
        shownSessions = nil
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
            shownSessions = nil
            return
        }
        guard !Task.isCancelled else {
            return
        }
        let points = bars.sorted { $0.sessionDate < $1.sessionDate }.map { ChartPoint(bar: $0) }
        let loaded = Loaded(sessions: sessions, points: points)
        charts[range] = loaded
        if self.range == range {
            show(loaded)
        }
    }

    private func show(_ loaded: Loaded) {
        state = loaded.points.isEmpty ? .empty : .loaded(loaded.points)
        shownSessions = loaded.sessions
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
