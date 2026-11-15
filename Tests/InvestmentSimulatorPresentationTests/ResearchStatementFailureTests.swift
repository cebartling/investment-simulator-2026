import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// How a statement table shows what it couldn't load: which failures drop a
/// column, and which empty or fail the section.
@MainActor
struct ResearchStatementFailureTests {
    private typealias Request = FakeStatements.Request

    private static let quarter3 = FiscalPeriod(year: 2026, part: .quarter3)
    private static let quarter2 = FiscalPeriod(year: 2026, part: .quarter2)
    private static let quarter1 = FiscalPeriod(year: 2026, part: .quarter1)
    private static let quarter4 = FiscalPeriod(year: 2025, part: .quarter4)
    private static let fy25 = FiscalPeriod(year: 2025, part: .fullYear)
    private static let fy24 = FiscalPeriod(year: 2024, part: .fullYear)
    private static let fy23 = FiscalPeriod(year: 2023, part: .fullYear)

    private static let quarterly = StatementSelection(kind: .income, cadence: .quarterly)
    private static let annual = StatementSelection(kind: .income, cadence: .annual)

    private static func statement(_ period: FiscalPeriod, _ amount: Decimal = 1) -> FinancialStatement {
        FinancialStatement(period: period, lines: [StatementLine(name: "Revenue", figure: .money(Money(amount)))])
    }

    private static func table(_ periods: FiscalPeriod...) -> StatementTable {
        StatementTable(statements: periods.map { statement($0) })
    }

    /// A company whose latest income statement is FY2026 Q3, with the
    /// periods both income tables need, and a balance sheet in Q3 alone.
    private static func statements() -> FakeStatements {
        var answers: [Request: Result<FinancialStatement, MarketDataError>] = [
            Request(.income, nil): .success(statement(quarter3)),
            Request(.balance, nil): .success(statement(quarter3)),
        ]
        for period in [quarter2, quarter1, quarter4, fy25, fy24, fy23] {
            answers[Request(.income, period)] = .success(statement(period))
        }
        return FakeStatements(answers)
    }

    @Test func `a period Equibles doesn't have drops its column`() async throws {
        let statements = FakeStatements([
            Request(.income, nil): .success(Self.statement(Self.quarter3)),
            Request(.income, Self.quarter1): .success(Self.statement(Self.quarter1)),
        ])
        let tab = try tab(statements)

        await tab.showStatements(Self.quarterly)

        #expect(tab.statementState == .loaded(Self.table(Self.quarter3, Self.quarter1)))
    }

    @Test func `no latest period is an empty section`() async throws {
        let statements = FakeStatements()
        let tab = try tab(statements)

        await tab.showStatements(Self.quarterly)

        #expect(tab.statementState == .empty(.noData))
        #expect(statements.requests.count == 1)
    }

    @Test func `no finished year is an empty section`() async throws {
        let statements = FakeStatements([Request(.income, nil): .success(Self.statement(Self.quarter3))])
        let tab = try tab(statements)

        await tab.showStatements(Self.annual)

        #expect(tab.statementState == .empty(.noData))
    }

    @Test func `finished years all in another currency say so rather than that there are none`() async throws {
        let statements = FakeStatements([
            Request(.income, nil): .success(Self.statement(Self.quarter3)),
            Request(.income, Self.fy25): .failure(.unsupportedCurrency),
            Request(.income, Self.fy24): .failure(.unsupportedCurrency),
            Request(.income, Self.fy23): .failure(.unsupportedCurrency),
        ])
        let tab = try tab(statements)

        await tab.showStatements(Self.annual)

        #expect(tab.statementState == .empty(.unsupportedCurrency))
    }

    @Test func `finished years only partly in another currency have no data`() async throws {
        let statements = FakeStatements([
            Request(.income, nil): .success(Self.statement(Self.quarter3)),
            Request(.income, Self.fy25): .failure(.unsupportedCurrency),
        ])
        let tab = try tab(statements)

        await tab.showStatements(Self.annual)

        #expect(tab.statementState == .empty(.noData))
    }

    @Test func `going back to an empty table asks for nothing`() async throws {
        let statements = FakeStatements([Request(.income, nil): .failure(.unsupportedCurrency)])
        let tab = try tab(statements)
        await tab.showStatements(Self.quarterly)
        await tab.showStatements(Self.annual)
        let sent = statements.requests.count

        await tab.showStatements(Self.quarterly)

        #expect(tab.statementState == .empty(.unsupportedCurrency))
        #expect(statements.requests.count == sent)
    }

    @Test func `a company reporting in another currency has statements the app can't show`() async throws {
        let statements = FakeStatements([Request(.income, nil): .failure(.unsupportedCurrency)])
        let tab = try tab(statements)

        await tab.showStatements(Self.quarterly)

        #expect(tab.statementState == .empty(.unsupportedCurrency))
        #expect(statements.requests.count == 1)
    }

    @Test func `a period in another currency drops its column`() async throws {
        let statements = FakeStatements([
            Request(.income, nil): .success(Self.statement(Self.quarter3)),
            Request(.income, Self.quarter2): .failure(.unsupportedCurrency),
            Request(.income, Self.quarter1): .success(Self.statement(Self.quarter1)),
        ])
        let tab = try tab(statements)

        await tab.showStatements(Self.quarterly)

        #expect(tab.statementState == .loaded(Self.table(Self.quarter3, Self.quarter1)))
    }

    @Test(arguments: [
        (MarketDataError.noData, true),
        (.unsupportedCurrency, true),
        (.missingAPIKey, false),
        (.invalidAPIKey, false),
        (.dailyLimitReached, false),
        (.unavailable("Down"), false),
        (.missingContactEmail, false),
    ])
    func `only a failure a retry can't help drops a period's column`(error: MarketDataError, drops: Bool) async throws {
        let statements = Self.statements()
        statements.answer(Request(.income, Self.quarter2), with: .failure(error))
        let tab = try tab(statements)

        await tab.showStatements(Self.quarterly)

        let expected: ResearchSectionState<StatementTable> = if drops {
            .loaded(Self.table(Self.quarter3, Self.quarter1, Self.quarter4))
        } else {
            .failed(error)
        }
        #expect(tab.statementState == expected)
    }

    @Test func `a failed latest period fails the section`() async throws {
        let statements = FakeStatements([Request(.income, nil): .failure(.dailyLimitReached)])
        let tab = try tab(statements)

        await tab.showStatements(Self.quarterly)

        #expect(tab.statementState == .failed(.dailyLimitReached))
    }

    @Test func `a failed older period fails the section rather than hide a column`() async throws {
        let statements = Self.statements()
        statements.answer(Request(.income, Self.quarter2), with: .failure(.unavailable("Down")))
        let tab = try tab(statements)

        await tab.showStatements(Self.quarterly)

        #expect(tab.statementState == .failed(.unavailable("Down")))
    }

    @Test func `showing a failed table again retries it without its latest period`() async throws {
        let statements = Self.statements()
        statements.answer(Request(.income, Self.quarter2), with: .failure(.unavailable("Down")))
        let tab = try tab(statements)
        await tab.showStatements(Self.quarterly)
        statements.answer(Request(.income, Self.quarter2), with: .success(Self.statement(Self.quarter2)))

        await tab.showStatements(Self.quarterly)

        #expect(tab.statementState == .loaded(Self.table(Self.quarter3, Self.quarter2, Self.quarter1, Self.quarter4)))
        #expect(statements.requests.count(where: { $0.period == nil }) == 1)
    }

    private func tab(_ statements: FakeStatements) throws -> ResearchTabModel {
        let data = FakeResearchData()
        return try ResearchTabModel(
            ticker: Ticker("VTI"),
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: FakeDailyPrices(),
            ports: ResearchSectionPorts(
                profiles: data,
                multiples: data,
                dividends: data,
                pressReleases: data,
                filings: data,
                statements: statements,
                directory: FakeDirectory(),
            ),
            clock: { Date(timeIntervalSince1970: 1_793_000_000) },
        )
    }
}
