import Foundation
import InvestmentSimulatorCore
import Observation

/// One open ticker in the Research window (ADR-0019): its quote and its
/// price history chart, each with its own state, so one failing leaves the
/// other showing.
@Observable
public final class ResearchTabModel: Identifiable {
    public enum QuoteState: Equatable {
        case loading
        case quoted(Quote)
        case failed(QuoteError)
    }

    public enum ChartState: Equatable {
        case loading
        /// Oldest first.
        case loaded([ChartPoint])
        case empty
        case failed(QuoteError)
    }

    public let ticker: Ticker
    public private(set) var quoteState = QuoteState.loading
    public private(set) var chartRange = PriceRange.sixMonths
    public private(set) var chartState = ChartState.loading

    private let quotes: any QuoteProviding
    private let dailyPrices: any DailyPriceProviding
    private let clock: () -> Date
    /// Each range's points once loaded, so going back to it asks for nothing.
    private var charts: [PriceRange: [ChartPoint]] = [:]

    public init(
        ticker: Ticker,
        quotes: any QuoteProviding,
        dailyPrices: any DailyPriceProviding,
        clock: @escaping () -> Date,
    ) {
        self.ticker = ticker
        self.quotes = quotes
        self.dailyPrices = dailyPrices
        self.clock = clock
    }

    public var id: Ticker {
        ticker
    }

    /// True when the quote failed for want of a working API key.
    public var needsAPIKey: Bool {
        quoteState == .failed(.missingAPIKey) || quoteState == .failed(.invalidAPIKey)
    }

    /// Quotes the ticker and charts the current range at the same time,
    /// forgetting the ranges loaded before. If the quote finds no such
    /// ticker, the chart is cancelled rather than waited for.
    public func load() async {
        charts = [:]
        let range = chartRange
        await withTaskGroup { group in
            group.addTask { await self.showRange(range) }
            await refresh()
            if case .failed(.unknownTicker) = quoteState {
                group.cancelAll()
            }
        }
    }

    /// Quotes the ticker again. A cancelled request changes nothing more: the
    /// ticker was closed, or a newer refresh took over.
    public func refresh() async {
        quoteState = .loading
        do throws(QuoteError) {
            let quote = try await quotes.quote(for: ticker)
            guard !Task.isCancelled else {
                return
            }
            quoteState = .quoted(quote)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            quoteState = .failed(error)
        }
    }

    /// Charts `range`, from memory if it was loaded before. A request
    /// cancelled before it starts changes nothing; one cancelled or
    /// superseded while loading changes nothing more.
    public func showRange(_ range: PriceRange) async {
        guard !Task.isCancelled else {
            return
        }
        chartRange = range
        if let points = charts[range] {
            show(points)
            return
        }
        chartState = .loading
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
            // The quote validates the ticker, so here a 404 means no
            // history: an empty state, not an error (ADR-0019).
            bars = []
        } catch {
            // A newer request may have charted this range already.
            guard !Task.isCancelled, chartRange == range, charts[range] == nil else {
                return
            }
            chartState = .failed(error)
            return
        }
        guard !Task.isCancelled else {
            return
        }
        let points = bars.sorted { $0.sessionDate < $1.sessionDate }.map(ChartPoint.init)
        charts[range] = points
        if chartRange == range {
            show(points)
        }
    }

    private func show(_ points: [ChartPoint]) {
        chartState = points.isEmpty ? .empty : .loaded(points)
    }
}

/// One bar's close, placed at noon of its New York session, so no daylight
/// saving change moves it to another day.
public nonisolated struct ChartPoint: Equatable, Sendable {
    public let date: Date
    public let close: Decimal

    private static let marketCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    init(bar: DailyBar) {
        let parts = bar.sessionDate.split(separator: "-").compactMap { Int($0) }
        date = Self.marketCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
        close = bar.close
    }
}
