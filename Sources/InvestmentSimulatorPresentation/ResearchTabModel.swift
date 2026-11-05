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
    /// Equibles has the data in a currency the app can't show.
    case unsupportedCurrency

    /// What the section says, where `subject` names what it shows, such as
    /// "press releases".
    public func message(subject: String, ticker: Ticker) -> String {
        switch self {
        case .noData: "No \(subject) for \(ticker.symbol)."
        case .nonePublished: "No \(subject) published for \(ticker.symbol)."
        case .notCovered: "Equibles doesn't cover \(ticker.symbol)'s \(subject)."
        case .unsupportedCurrency: "\(ticker.symbol)'s \(subject) are in a currency the app can't show."
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
    /// SEC's company ID for the ticker, once the directory has listed it. It
    /// stays nil when EDGAR is off, fails or lacks the ticker; a later failed
    /// lookup keeps the last good one.
    private var cik: Int?
    public private(set) var multiplesState = ResearchSectionState<ValuationMultiples>.loading
    public private(set) var dividendsState = ResearchSectionState<DividendHistory>.loading
    public private(set) var pressReleasesState = ResearchSectionState<[PressRelease]>.loading
    public private(set) var filingsState = ResearchSectionState<[Filing]>.loading
    public private(set) var statementSelection = StatementSelection(kind: .income, cadence: .quarterly)
    public private(set) var statementState = ResearchSectionState<StatementTable>.loading
    /// The pane shown below the header. Statements load only once Financials
    /// is selected, as each costs several requests. Kept while the ticker is
    /// open, so a closed and reopened ticker starts on Overview; the window
    /// model's `selectPane` changes it.
    public internal(set) var selectedPane = ResearchPane.overview

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

    /// The trailing dividend yield at the current quote, or nil until both
    /// are in. Worked out here so a refreshed quote updates it.
    public var dividendYield: Decimal? {
        guard case let .loaded(history) = dividendsState, case let .quoted(quote) = quoteState else {
            return nil
        }
        return history.trailingYield(atPrice: quote.price)
    }

    /// Forgets the statements loaded before. A full load starts from here, so
    /// the statement shown can reload apart from `load()`, where the window
    /// model can cancel it.
    public func forgetStatements() {
        tables = [:]
        latestStatements = [:]
    }

    /// Quotes the ticker, charts the current range and loads the sections at
    /// the same time, forgetting the ranges loaded before. Statements are left
    /// alone: callers `forgetStatements()` first and reload the one shown
    /// themselves. If the quote finds no such ticker, the rest is cancelled
    /// rather than waited for. The exchange waits for the quote: a directory
    /// download can't be cancelled, so it would hold up dropping an unknown
    /// ticker. A load cancelled before it starts changes nothing.
    public func load() async {
        guard !Task.isCancelled else {
            return
        }
        charts = [:]
        let range = chartRange
        await withTaskGroup { group in
            group.addTask { await self.showRange(range) }
            for section in Section.allCases where section != .exchange {
                group.addTask { await self.load(section) }
            }
            await refresh()
            if case .failed(.unknownTicker) = quoteState {
                group.cancelAll()
            } else {
                group.addTask { await self.load(.exchange) }
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
        let points = bars.sorted { $0.sessionDate < $1.sessionDate }.map { ChartPoint(bar: $0) }
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
        } catch {
            outcome = error.sectionState()
        }
        if !Task.isCancelled, statementSelection == selection {
            statementState = outcome
        }
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
                let security = try await ports.directory.security(for: ticker)
                if !Task.isCancelled {
                    cik = security?.cik
                }
                guard let exchange = security?.exchange else {
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
        } catch {
            outcome = error.sectionState()
        }
        if !Task.isCancelled {
            self[keyPath: state] = outcome
        }
    }
}

public extension ResearchTabModel {
    /// Where a filing row opens: its folder on sec.gov when EDGAR has listed
    /// the ticker, otherwise the Equibles page.
    func link(for filing: Filing) -> URL {
        cik.flatMap(filing.secURL(cik:)) ?? filing.url
    }

    /// Why the profile shows no exchange, when that's worth saying.
    var exchangeMessage: String? {
        switch exchangeState {
        case .failed(.missingContactEmail): "Add your SEC contact email in Settings to see the exchange."
        case let .failed(error): error.localizedDescription
        case .loading, .loaded, .empty: nil
        }
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
