import Foundation
import InvestmentSimulatorCore
import Observation

/// One Research section's progress (ADR-0019).
public nonisolated enum ResearchSectionState<Value: Equatable>: Equatable {
    case loading
    case loaded(Value)
    /// Equibles has nothing to show for this ticker.
    case empty
    case failed(MarketDataError)
}

/// One open ticker in the Research window (ADR-0019): its quote, price
/// history chart and sections, each with its own state, so one failing
/// leaves the others showing.
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

    /// The parts of a ticker's research that load through a section port.
    public nonisolated enum Section: CaseIterable, Sendable {
        case profile
        case multiples
        case dividends
    }

    public let ticker: Ticker
    public private(set) var quoteState = QuoteState.loading
    public private(set) var chartRange = PriceRange.sixMonths
    public private(set) var chartState = ChartState.loading
    public private(set) var profileState = ResearchSectionState<CompanyProfile>.loading
    public private(set) var multiplesState = ResearchSectionState<ValuationMultiples>.loading
    public private(set) var dividendsState = ResearchSectionState<DividendHistory>.loading

    private let quotes: any QuoteProviding
    private let dailyPrices: any DailyPriceProviding
    private let profiles: any CompanyProfileProviding
    private let multiples: any ValuationMultiplesProviding
    private let dividends: any DividendProviding
    private let clock: () -> Date
    /// Each range's points once loaded, so going back to it asks for nothing.
    private var charts: [PriceRange: [ChartPoint]] = [:]

    public init(
        ticker: Ticker,
        quotes: any QuoteProviding,
        dailyPrices: any DailyPriceProviding,
        profiles: any CompanyProfileProviding,
        multiples: any ValuationMultiplesProviding,
        dividends: any DividendProviding,
        clock: @escaping () -> Date,
    ) {
        self.ticker = ticker
        self.quotes = quotes
        self.dailyPrices = dailyPrices
        self.profiles = profiles
        self.multiples = multiples
        self.dividends = dividends
        self.clock = clock
    }

    public var id: Ticker {
        ticker
    }

    /// True when the quote failed for want of a working API key.
    public var needsAPIKey: Bool {
        quoteState == .failed(.missingAPIKey) || quoteState == .failed(.invalidAPIKey)
    }

    /// The trailing dividend yield at the current quote, or nil until both
    /// are in. Worked out here so a refreshed quote updates it.
    public var dividendYield: Decimal? {
        guard case let .loaded(history) = dividendsState, case let .quoted(quote) = quoteState else {
            return nil
        }
        return history.trailingYield(atPrice: quote.price)
    }

    /// Quotes the ticker, charts the current range and loads the sections at
    /// the same time, forgetting the ranges loaded before. If the quote finds
    /// no such ticker, the rest is cancelled rather than waited for. A load
    /// cancelled before it starts changes nothing.
    public func load() async {
        guard !Task.isCancelled else {
            return
        }
        charts = [:]
        let range = chartRange
        await withTaskGroup { group in
            group.addTask { await self.showRange(range) }
            for section in Section.allCases {
                group.addTask { await self.load(section) }
            }
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

    /// Loads one section, leaving the rest as they are. A request cancelled
    /// before it starts changes nothing; one cancelled while loading changes
    /// nothing more.
    public func load(_ section: Section) async {
        switch section {
        case .profile:
            await load(\.profileState) { () async throws(MarketDataError) in
                try await profiles.companyProfile(for: ticker)
            }
        case .multiples:
            await load(\.multiplesState) { () async throws(MarketDataError) in
                try await multiples.valuationMultiples(for: ticker)
            }
        case .dividends:
            await load(\.dividendsState) { () async throws(MarketDataError) in
                try await DividendHistory(dividends: dividends.dividends(for: ticker), asOf: clock())
            }
        }
    }

    private func load<Value>(
        _ state: ReferenceWritableKeyPath<ResearchTabModel, ResearchSectionState<Value>>,
        from request: () async throws(MarketDataError) -> Value,
    ) async {
        guard !Task.isCancelled else {
            return
        }
        self[keyPath: state] = .loading
        let outcome: ResearchSectionState<Value>
        do throws(MarketDataError) {
            outcome = try await .loaded(request())
        } catch .noData {
            outcome = .empty
        } catch {
            outcome = .failed(error)
        }
        if !Task.isCancelled {
            self[keyPath: state] = outcome
        }
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
