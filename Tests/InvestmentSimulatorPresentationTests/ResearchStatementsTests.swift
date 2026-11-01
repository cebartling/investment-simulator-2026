import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct ResearchStatementsTests {
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
    private static let balance = StatementSelection(kind: .balance, cadence: .quarterly)

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

    @Test func `opening a ticker asks for no statements`() async throws {
        let statements = Self.statements()
        let tab = try tab(statements)

        await tab.load()

        #expect(statements.requests.isEmpty)
        #expect(tab.statementsShown == false)
        #expect(tab.statementState == .loading)
    }

    @Test func `showing a statement fills in the latest four quarters, newest first`() async throws {
        let statements = Self.statements()
        let tab = try tab(statements)

        await tab.showStatements(Self.quarterly)

        #expect(tab.statementsShown)
        #expect(tab.statementSelection == Self.quarterly)
        #expect(tab.statementState == .loaded(Self.table(Self.quarter3, Self.quarter2, Self.quarter1, Self.quarter4)))
        #expect(statements.requests.count == 4)
    }

    @Test func `annual periods reuse the latest period already known`() async throws {
        let statements = Self.statements()
        let tab = try tab(statements)
        await tab.showStatements(Self.quarterly)

        await tab.showStatements(Self.annual)

        #expect(tab.statementState == .loaded(Self.table(Self.fy25, Self.fy24, Self.fy23)))
        #expect(statements.requests.count == 7)
    }

    @Test func `annual periods alone find the latest period first`() async throws {
        let statements = Self.statements()
        let tab = try tab(statements)

        await tab.showStatements(Self.annual)

        #expect(tab.statementState == .loaded(Self.table(Self.fy25, Self.fy24, Self.fy23)))
        #expect(statements.requests.count == 4)
    }

    @Test func `a latest period that is a column isn't asked for twice`() async throws {
        let statements = FakeStatements([
            Request(.income, nil): .success(Self.statement(Self.fy25)),
            Request(.income, Self.fy24): .success(Self.statement(Self.fy24)),
        ])
        let tab = try tab(statements)

        await tab.showStatements(Self.annual)

        #expect(tab.statementState == .loaded(Self.table(Self.fy25, Self.fy24)))
        #expect(Set(statements.requests) == [
            Request(.income, nil),
            Request(.income, Self.fy24),
            Request(.income, Self.fy23),
        ])
        #expect(statements.requests.count == 3)
    }

    @Test func `going back to a table asks for nothing`() async throws {
        let statements = Self.statements()
        let tab = try tab(statements)
        await tab.showStatements(Self.quarterly)
        await tab.showStatements(Self.annual)
        let sent = statements.requests.count

        await tab.showStatements(Self.quarterly)

        #expect(tab.statementState == .loaded(Self.table(Self.quarter3, Self.quarter2, Self.quarter1, Self.quarter4)))
        #expect(statements.requests.count == sent)
    }

    @Test func `another statement finds its own latest period`() async throws {
        let statements = Self.statements()
        let tab = try tab(statements)
        await tab.showStatements(Self.quarterly)

        await tab.showStatements(Self.balance)

        #expect(tab.statementState == .loaded(Self.table(Self.quarter3)))
        #expect(statements.requests.contains(Request(.balance, nil)))
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

    @Test func `a request cancelled before it starts changes nothing`() async throws {
        let statements = Self.statements()
        let tab = try tab(statements)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await tab.showStatements(Self.quarterly)
        }
        await task.value

        #expect(tab.statementsShown == false)
        #expect(statements.requests.isEmpty)
    }

    @Test func `a request cancelled while loading changes nothing more`() async throws {
        let statements = Self.statements()
        let tab = try tab(statements)
        let run = Run()
        statements.whileAnswering { run.task?.cancel() }

        run.task = Task { await tab.showStatements(Self.quarterly) }
        await run.task?.value

        #expect(tab.statementState == .loading)
    }

    @Test func `a superseded table doesn't replace the one shown`() async throws {
        let statements = Self.statements()
        let tab = try tab(statements)
        await tab.showStatements(Self.balance)
        let run = Run()
        statements.whileAnswering {
            guard run.task == nil else {
                return
            }
            run.task = Task { await tab.showStatements(Self.balance) }
        }

        await tab.showStatements(Self.quarterly)
        statements.whileAnswering {}
        await run.task?.value

        #expect(tab.statementSelection == Self.balance)
        #expect(tab.statementState == .loaded(Self.table(Self.quarter3)))
    }

    @Test func `hiding statements keeps what loaded`() async throws {
        let statements = Self.statements()
        let tab = try tab(statements)
        await tab.showStatements(Self.quarterly)
        let sent = statements.requests.count

        tab.hideStatements()
        #expect(tab.statementsShown == false)
        await tab.showStatements(Self.quarterly)

        #expect(tab.statementState == .loaded(Self.table(Self.quarter3, Self.quarter2, Self.quarter1, Self.quarter4)))
        #expect(statements.requests.count == sent)
    }

    @Test func `loading again forgets statements and reloads the one shown`() async throws {
        let statements = Self.statements()
        let tab = try tab(statements)
        await tab.showStatements(Self.quarterly)
        let sent = statements.requests.count
        statements.answer(Request(.income, nil), with: .success(Self.statement(Self.quarter3, 5)))

        await tab.load()

        #expect(statements.requests.count == sent * 2)
        #expect(tab.statementState == .loaded(StatementTable(statements: [
            Self.statement(Self.quarter3, 5),
            Self.statement(Self.quarter2),
            Self.statement(Self.quarter1),
            Self.statement(Self.quarter4),
        ])))
    }

    @Test func `loading again leaves hidden statements unloaded`() async throws {
        let statements = Self.statements()
        let tab = try tab(statements)
        await tab.showStatements(Self.quarterly)
        tab.hideStatements()
        let sent = statements.requests.count

        await tab.load()
        #expect(statements.requests.count == sent)

        await tab.showStatements(Self.quarterly)
        #expect(statements.requests.count == sent * 2)
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

@MainActor
private final class Run {
    var task: Task<Void, Never>?
}
