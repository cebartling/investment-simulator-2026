import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct ResearchWindowModelStatementsTests {
    private static let quarter3 = FiscalPeriod(year: 2026, part: .quarter3)
    private static let quarterly = StatementSelection(kind: .income, cadence: .quarterly)
    private static let balance = StatementSelection(kind: .balance, cadence: .quarterly)

    private static func statement() -> FinancialStatement {
        FinancialStatement(period: quarter3, lines: [StatementLine(name: "Revenue", figure: .money(Money(1)))])
    }

    private static func table() -> StatementTable {
        StatementTable(statements: [statement()])
    }

    /// Latest income and balance sheet, with no older periods.
    private static func statements() -> FakeStatements {
        FakeStatements([
            FakeStatements.Request(.income, nil): .success(statement()),
            FakeStatements.Request(.balance, nil): .success(statement()),
        ])
    }

    @Test func `the window model shows statements for an open ticker`() async throws {
        let statements = Self.statements()
        let model = research(statements)
        let task = model.open()
        await task?.value
        let vti = try Ticker("VTI")

        await model.showStatements(Self.quarterly, for: vti)?.value

        #expect(model.selectedTab?.statementState == .loaded(Self.table()))
        model.hideStatements(for: vti)
        #expect(model.selectedTab?.statementsShown == false)
    }

    @Test func `the window model shows nothing for a closed ticker`() throws {
        let model = research(Self.statements())

        #expect(try model.showStatements(Self.quarterly, for: Ticker("VTI")) == nil)
    }

    @Test func `a newer selection cancels the one loading`() async throws {
        let statements = Self.statements()
        let model = research(statements)
        await model.open()?.value
        let vti = try Ticker("VTI")
        let run = Run()
        statements.whileAnswering {
            guard run.task == nil else {
                return
            }
            run.task = model.showStatements(Self.balance, for: vti)
        }

        let superseded = model.showStatements(Self.quarterly, for: vti)
        await superseded?.value
        await run.task?.value

        #expect(superseded?.isCancelled == true)
        #expect(model.selectedTab?.statementSelection == Self.balance)
        #expect(model.selectedTab?.statementState == .loaded(Self.table()))
    }

    @Test func `hiding statements cancels the one loading`() async throws {
        let statements = Self.statements()
        let model = research(statements)
        await model.open()?.value
        let vti = try Ticker("VTI")
        let tab = try #require(model.selectedTab)
        statements.whileAnswering { model.hideStatements(for: vti) }

        await model.showStatements(Self.quarterly, for: vti)?.value

        #expect(tab.statementState == .loading)
        #expect(tab.statementsShown == false)
    }

    @Test func `closing a ticker cancels its statements`() async throws {
        let statements = Self.statements()
        let model = research(statements)
        await model.open()?.value
        let vti = try Ticker("VTI")
        let tab = try #require(model.selectedTab)
        statements.whileAnswering { model.close(vti) }

        await model.showStatements(Self.quarterly, for: vti)?.value

        #expect(tab.statementState == .loading)
    }

    private func research(_ statements: FakeStatements) -> ResearchWindowModel {
        let data = FakeResearchData()
        let model = ResearchWindowModel(
            quotes: FakeTickerQuotes(["VTI": .failure(.missingAPIKey)]),
            dailyPrices: FakeDailyPrices(),
            ports: ResearchSectionPorts(
                profiles: data,
                multiples: data,
                dividends: data,
                pressReleases: data,
                filings: data,
                statements: statements,
            ),
            clock: { Date(timeIntervalSince1970: 1_793_000_000) },
        )
        model.symbolText = "VTI"
        return model
    }
}

@MainActor
private final class Run {
    var task: Task<Void, Never>?
}
