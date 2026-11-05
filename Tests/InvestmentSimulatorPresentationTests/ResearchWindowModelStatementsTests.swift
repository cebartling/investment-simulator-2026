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
    }

    @Test func `a ticker opens on Overview and asks for no statements`() async {
        let statements = Self.statements()
        let model = research(statements)

        await model.open()?.value

        #expect(model.selectedTab?.selectedPane == .overview)
        #expect(statements.requests.isEmpty)
    }

    @Test func `selecting Financials loads the statement shown`() async throws {
        let model = research(Self.statements())
        await model.open()?.value
        let vti = try Ticker("VTI")

        await model.selectPane(.financials, for: vti)?.value

        #expect(model.selectedTab?.selectedPane == .financials)
        #expect(model.selectedTab?.statementState == .loaded(Self.table()))
    }

    @Test func `selecting another pane asks for no statements`() async throws {
        let statements = Self.statements()
        let model = research(statements)
        await model.open()?.value
        let vti = try Ticker("VTI")

        #expect(model.selectPane(.dividends, for: vti) == nil)

        #expect(model.selectedTab?.selectedPane == .dividends)
        #expect(statements.requests.isEmpty)
    }

    @Test func `each ticker keeps the pane it was left on`() async throws {
        let model = research(Self.statements())
        await model.open()?.value
        let vti = try Ticker("VTI")
        model.selectPane(.filings, for: vti)
        model.symbolText = "VOO"
        await model.open()?.value

        try model.selectPane(.news, for: Ticker("VOO"))

        #expect(model.tabs.first { $0.ticker == vti }?.selectedPane == .filings)
        #expect(model.selectedTab?.selectedPane == .news)
    }

    @Test func `reselecting Financials uses the table already loaded`() async throws {
        let statements = Self.statements()
        let model = research(statements)
        await model.open()?.value
        let vti = try Ticker("VTI")
        await model.selectPane(.financials, for: vti)?.value
        model.selectPane(.overview, for: vti)
        let before = statements.requests.count

        await model.selectPane(.financials, for: vti)?.value

        #expect(model.selectedTab?.statementState == .loaded(Self.table()))
        #expect(statements.requests.count == before)
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

    @Test func `leaving Financials cancels the statement loading`() async throws {
        let statements = Self.statements()
        let model = research(statements)
        await model.open()?.value
        let vti = try Ticker("VTI")
        let tab = try #require(model.selectedTab)
        statements.whileAnswering { model.selectPane(.overview, for: vti) }

        await model.selectPane(.financials, for: vti)?.value

        #expect(tab.statementState == .loading)
        #expect(tab.selectedPane == .overview)
    }

    @Test func `leaving Financials cancels the reload a refresh started`() async throws {
        let statements = Self.statements()
        let model = research(statements)
        await model.open()?.value
        let vti = try Ticker("VTI")
        let tab = try #require(model.selectedTab)
        await model.selectPane(.financials, for: vti)?.value
        statements.whileAnswering { model.selectPane(.overview, for: vti) }

        await model.refresh(vti)?.value

        #expect(tab.statementState == .loading)
        #expect(tab.selectedPane == .overview)
    }

    @Test func `selecting the pane already shown loads nothing again`() async throws {
        let statements = Self.statements()
        let model = research(statements)
        await model.open()?.value
        let vti = try Ticker("VTI")
        let again = Run()
        statements.whileAnswering {
            guard again.task == nil else {
                return
            }
            again.task = model.selectPane(.financials, for: vti)
            again.ran = true
        }

        let first = model.selectPane(.financials, for: vti)
        await first?.value

        #expect(again.ran)
        #expect(again.task == nil)
        #expect(first?.isCancelled == false)
        #expect(model.selectedTab?.statementState == .loaded(Self.table()))
    }

    @Test func `a refresh reloads statements only while Financials is selected`() async throws {
        let statements = Self.statements()
        let model = research(statements)
        await model.open()?.value
        let vti = try Ticker("VTI")
        await model.selectPane(.financials, for: vti)?.value
        var count = statements.requests.count

        // The reload runs as its own task, so let it finish before counting.
        await model.refresh(vti)?.value
        await settle()
        #expect(statements.requests.count > count)

        model.selectPane(.valuation, for: vti)
        count = statements.requests.count
        await model.refresh(vti)?.value
        await settle()

        #expect(statements.requests.count == count)
    }

    @Test func `a newer selection cancels the reload a refresh started`() async throws {
        let statements = Self.statements()
        let model = research(statements)
        await model.open()?.value
        let vti = try Ticker("VTI")
        let tab = try #require(model.selectedTab)
        await model.selectPane(.financials, for: vti)?.value
        let run = Run()
        statements.whileAnswering {
            guard run.task == nil else {
                return
            }
            run.task = model.showStatements(Self.balance, for: vti)
        }

        await model.refresh(vti)?.value
        await run.task?.value

        #expect(tab.statementSelection == Self.balance)
        #expect(tab.statementState == .loaded(Self.table()))
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
            quotes: FakeTickerQuotes(["VTI": .failure(.missingAPIKey), "VOO": .failure(.missingAPIKey)]),
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
            tickerStore: NoResearchTickerStore(),
            clock: { Date(timeIntervalSince1970: 1_793_000_000) },
        )
        model.symbolText = "VTI"
        return model
    }
}

@MainActor
private final class Run {
    var task: Task<Void, Never>?
    var ran = false
}

/// Lets tasks that are ready run, as the fakes answer without waiting.
@MainActor
private func settle() async {
    for _ in 0 ..< 50 {
        await Task.yield()
    }
}
