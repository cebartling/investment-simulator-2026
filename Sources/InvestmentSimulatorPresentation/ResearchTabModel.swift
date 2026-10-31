import Foundation
import InvestmentSimulatorCore
import Observation

/// Why a Research section has nothing to show (ADR-0019).
public nonisolated enum ResearchEmptyReason: Equatable, Sendable {
    /// Equibles has nothing to show for this ticker.
    case noData
    /// Equibles covers the company, and it published nothing.
    case nonePublished
    /// Equibles' coverage of the company is missing or incomplete.
    case notCovered

    /// What the section says, where `subject` names what it shows, such as
    /// "press releases".
    public func message(subject: String, ticker: Ticker) -> String {
        switch self {
        case .noData: "No \(subject) for \(ticker.symbol)."
        case .nonePublished: "No \(subject) published for \(ticker.symbol)."
        case .notCovered: "Equibles doesn't cover \(ticker.symbol)'s \(subject)."
        }
    }
}

/// One Research section's progress (ADR-0019).
public nonisolated enum ResearchSectionState<Value: Equatable>: Equatable {
    case loading
    case loaded(Value)
    case empty(ResearchEmptyReason)
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
        case exchange
        case multiples
        case dividends
        case pressReleases
        case filings
    }

    public let ticker: Ticker
    public private(set) var quoteState = QuoteState.loading
    public private(set) var chartRange = PriceRange.sixMonths
    public private(set) var chartState = ChartState.loading
    public private(set) var profileState = ResearchSectionState<CompanyProfile>.loading
    /// Empty when EDGAR doesn't list the ticker, or lists no exchange for it.
    public private(set) var exchangeState = ResearchSectionState<String>.loading
    public private(set) var multiplesState = ResearchSectionState<ValuationMultiples>.loading
    public private(set) var dividendsState = ResearchSectionState<DividendHistory>.loading
    public private(set) var pressReleasesState = ResearchSectionState<[PressRelease]>.loading
    public private(set) var filingsState = ResearchSectionState<[Filing]>.loading
    public private(set) var statementSelection = StatementSelection(kind: .income, cadence: .quarterly)
    public private(set) var statementState = ResearchSectionState<StatementTable>.loading
    /// Statements load only once shown, as each costs several requests.
    public private(set) var statementsShown = false

    private let quotes: any QuoteProviding
    private let dailyPrices: any DailyPriceProviding
    private let ports: ResearchSectionPorts
    private let clock: () -> Date
    /// Each range's points once loaded, so going back to it asks for nothing.
    private var charts: [PriceRange: [ChartPoint]] = [:]
    /// Each table once loaded, so going back to it asks for nothing.
    private var tables: [StatementSelection: StatementTable] = [:]
    /// Each statement's newest period, where the walk back starts from.
    private var latestStatements: [StatementKind: FinancialStatement] = [:]

    public init(
        ticker: Ticker,
        quotes: any QuoteProviding,
        dailyPrices: any DailyPriceProviding,
        ports: ResearchSectionPorts,
        clock: @escaping () -> Date,
    ) {
        self.ticker = ticker
        self.quotes = quotes
        self.dailyPrices = dailyPrices
        self.ports = ports
        self.clock = clock
    }

    public var id: Ticker {
        ticker
    }

    /// True when the quote failed for want of a working API key.
    public var needsAPIKey: Bool {
        quoteState == .failed(.missingAPIKey) || quoteState == .failed(.invalidAPIKey)
    }

    /// Why the profile shows no exchange, when that's worth saying.
    public var exchangeMessage: String? {
        switch exchangeState {
        case .failed(.missingContactEmail): "Add your SEC contact email in Settings to see the exchange."
        case let .failed(error): error.localizedDescription
        case .loading, .loaded, .empty: nil
        }
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
    /// the same time, forgetting the ranges and statements loaded before.
    /// Statements reload only if they're showing. If the quote finds
    /// no such ticker, the rest is cancelled rather than waited for. A load
    /// cancelled before it starts changes nothing.
    public func load() async {
        guard !Task.isCancelled else {
            return
        }
        charts = [:]
        tables = [:]
        latestStatements = [:]
        let range = chartRange
        let selection = statementsShown ? statementSelection : nil
        await withTaskGroup { group in
            group.addTask { await self.showRange(range) }
            if let selection {
                group.addTask { await self.showStatements(selection) }
            }
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

    /// Shows a statement's table, from memory if it was loaded before. A
    /// request cancelled before it starts changes nothing; one cancelled or
    /// superseded while loading changes nothing more.
    public func showStatements(_ selection: StatementSelection) async {
        guard !Task.isCancelled else {
            return
        }
        statementsShown = true
        statementSelection = selection
        if let table = tables[selection] {
            statementState = .loaded(table)
            return
        }
        statementState = .loading
        let outcome: ResearchSectionState<StatementTable>
        do throws(MarketDataError) {
            let table = try await table(for: selection)
            guard !Task.isCancelled else {
                return
            }
            tables[selection] = table
            outcome = .loaded(table)
        } catch .noData {
            outcome = .empty(.noData)
        } catch {
            outcome = .failed(error)
        }
        if !Task.isCancelled, statementSelection == selection {
            statementState = outcome
        }
    }

    /// Stops showing statements, keeping the tables loaded.
    public func hideStatements() {
        statementsShown = false
    }

    private func table(for selection: StatementSelection) async throws(MarketDataError) -> StatementTable {
        let loader = StatementTableLoader(statements: ports.statements, ticker: ticker)
        let latest: FinancialStatement
        if let known = latestStatements[selection.kind] {
            latest = known
        } else {
            latest = try await loader.latest(selection.kind)
            if !Task.isCancelled {
                latestStatements[selection.kind] = latest
            }
        }
        return try await loader.table(selection, endingAt: latest)
    }

    /// Loads one section, leaving the rest as they are. A request cancelled
    /// before it starts changes nothing; one cancelled while loading changes
    /// nothing more.
    public func load(_ section: Section) async {
        switch section {
        case .profile:
            await load(\.profileState) { () async throws(MarketDataError) in
                try await .loaded(ports.profiles.companyProfile(for: ticker))
            }
        case .exchange:
            await load(\.exchangeState) { () async throws(MarketDataError) in
                guard let exchange = try await ports.directory.security(for: ticker)?.exchange else {
                    return .empty(.noData)
                }
                return .loaded(exchange)
            }
        case .multiples:
            await load(\.multiplesState) { () async throws(MarketDataError) in
                try await .loaded(ports.multiples.valuationMultiples(for: ticker))
            }
        case .dividends:
            await load(\.dividendsState) { () async throws(MarketDataError) in
                try await .loaded(DividendHistory(dividends: ports.dividends.dividends(for: ticker), asOf: clock()))
            }
        case .pressReleases:
            await load(\.pressReleasesState) { () async throws(MarketDataError) in
                try await state(of: ports.pressReleases.pressReleases(for: ticker))
            }
        case .filings:
            await load(\.filingsState) { () async throws(MarketDataError) in
                try await .loaded(ports.filings.filings(for: ticker).sorted { $0.filedDate > $1.filedDate })
            }
        }
    }

    /// Only Equibles having read a company's site makes an empty list mean
    /// nothing was published.
    private func state(of result: PressReleases) -> ResearchSectionState<[PressRelease]> {
        guard !result.releases.isEmpty else {
            return .empty(result.coverage == .scraped ? .nonePublished : .notCovered)
        }
        return .loaded(result.releases.sorted { $0.publishedAt > $1.publishedAt })
    }

    private func load<Value>(
        _ state: ReferenceWritableKeyPath<ResearchTabModel, ResearchSectionState<Value>>,
        from request: () async throws(MarketDataError) -> ResearchSectionState<Value>,
    ) async {
        guard !Task.isCancelled else {
            return
        }
        self[keyPath: state] = .loading
        let outcome: ResearchSectionState<Value>
        do throws(MarketDataError) {
            outcome = try await request()
        } catch .noData {
            outcome = .empty(.noData)
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
