import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorMarketData
import Testing

struct EquiblesFinancialStatementsTests {
    let aapl: Ticker

    init() throws {
        aapl = try Ticker("AAPL")
    }

    static let income = "/v1/stocks/AAPL/financial-statements/income"
    static let balance = "/v1/stocks/AAPL/financial-statements/balance"
    static let cashFlow = "/v1/stocks/AAPL/financial-statements/cashflow"
    static let unreadable = MarketDataError.unavailable("Equibles sent a response the app couldn't read.")

    /// As Equibles sent it on 2026-10-29 (`docs/spikes/PIN-413`), trimmed to
    /// one line of each unit.
    static let latestIncome = #"""
    {"ticker": "AAPL", "companyName": "Apple Inc.", "statement": "income",
     "fiscalYear": 2026, "fiscalPeriod": "Q3",
     "data": [{"lineItem": "Revenue", "value": 109417000000.0, "unit": "USD", "basis": "reported"},
              {"lineItem": "EPS (Basic)", "value": 2.03, "unit": "USD/shares", "splitBasis": "today"},
              {"lineItem": "Shares Outstanding (Basic Avg)", "value": 14656110000.0, "unit": "shares"}]}
    """#

    /// Fourth quarters are derived: no EPS or share lines.
    static let derivedQ4 = #"""
    {"fiscalYear": 2025, "fiscalPeriod": "Q4",
     "data": [{"lineItem": "Revenue", "value": 102466000000.0, "unit": "USD", "basis": "derived"}]}
    """#

    static let negative = #"""
    {"fiscalYear": 2026, "fiscalPeriod": "Q3",
     "data": [{"lineItem": "Accumulated Other Comprehensive Income", "value": -4508000000.0, "unit": "USD"}]}
    """#

    static let fullYear = #"""
    {"fiscalYear": 2025, "fiscalPeriod": "FY",
     "data": [{"lineItem": "Total Assets", "value": 5024265535488.0, "unit": "USD"}]}
    """#

    static let missing = #"""
    {"error": {"code": "not_found", "message": "No income statement line items were found.", "status": 404}}
    """#

    @Test func `the latest statement has each unit's figure`() async throws {
        let transport = FakeTransport([Self.income: (200, Self.latestIncome)])

        let statement = try await provider(transport).financialStatement(.income, for: aapl, period: nil)

        let eps = try #require(Decimal(string: "2.03"))
        #expect(statement == FinancialStatement(
            period: FiscalPeriod(year: 2026, part: .q3),
            lines: [
                StatementLine(name: "Revenue", figure: .money(Money(109_417_000_000))),
                StatementLine(name: "EPS (Basic)", figure: .perShare(eps)),
                StatementLine(name: "Shares Outstanding (Basic Avg)", figure: .shares(14_656_110_000)),
            ],
        ))
    }

    @Test func `the latest statement asks for no period`() async throws {
        let transport = FakeTransport([Self.income: (200, Self.latestIncome)])

        _ = try await provider(transport, key: "eq_secret").financialStatement(.income, for: aapl, period: nil)

        let request = try #require(transport.requests.first)
        #expect(request.url?.query() == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer eq_secret")
    }

    @Test func `a quarter asks for its year and period`() async throws {
        let transport = FakeTransport(["\(Self.income)?year=2025&period=Q4": (200, Self.derivedQ4)])
        let period = FiscalPeriod(year: 2025, part: .q4)

        let statement = try await provider(transport).financialStatement(.income, for: aapl, period: period)

        #expect(statement.period == period)
        #expect(statement.lines == [StatementLine(name: "Revenue", figure: .money(Money(102_466_000_000)))])
    }

    @Test func `a full year is the FY period, with a trillion-scale figure kept exact`() async throws {
        let transport = FakeTransport(["\(Self.balance)?year=2025&period=FY": (200, Self.fullYear)])
        let period = FiscalPeriod(year: 2025, part: .fullYear)

        let statement = try await provider(transport).financialStatement(.balance, for: aapl, period: period)

        #expect(statement.period == period)
        #expect(statement.lines == [StatementLine(name: "Total Assets", figure: .money(Money(5_024_265_535_488)))])
    }

    @Test func `the cash flow statement has its own path`() async throws {
        let transport = FakeTransport([Self.cashFlow: (200, Self.latestIncome)])

        _ = try await provider(transport).financialStatement(.cashFlow, for: aapl, period: nil)

        #expect(transport.requests.count == 1)
    }

    @Test func `a negative figure stays negative`() async throws {
        let transport = FakeTransport([Self.balance: (200, Self.negative)])

        let statement = try await provider(transport).financialStatement(.balance, for: aapl, period: nil)

        #expect(statement.lines.first?.figure == .money(Money(-4_508_000_000)))
    }

    @Test func `a line in another currency is left out`() async throws {
        let body = #"""
        {"fiscalYear": 2026, "fiscalPeriod": "Q3",
         "data": [{"lineItem": "Revenue", "value": 5.0, "unit": "TWD"},
                  {"lineItem": "EPS (Basic)", "value": 1.5, "unit": "USD/shares"}]}
        """#
        let transport = FakeTransport([Self.income: (200, body)])

        let statement = try await provider(transport).financialStatement(.income, for: aapl, period: nil)

        #expect(statement.lines.map(\.name) == ["EPS (Basic)"])
    }

    @Test func `a line missing a field is left out`() async throws {
        let body = #"""
        {"fiscalYear": 2026, "fiscalPeriod": "Q3",
         "data": [{"lineItem": "Revenue", "value": null, "unit": "USD"},
                  {"value": 1.0, "unit": "USD"},
                  {"lineItem": "Net Income", "value": 2.0, "unit": null},
                  {"lineItem": "Gross Profit", "value": 3.0, "unit": "USD"}]}
        """#
        let transport = FakeTransport([Self.income: (200, body)])

        let statement = try await provider(transport).financialStatement(.income, for: aapl, period: nil)

        #expect(statement.lines.map(\.name) == ["Gross Profit"])
    }

    @Test func `no readable line at all is unavailable`() async throws {
        let body = #"""
        {"fiscalYear": 2026, "fiscalPeriod": "Q3",
         "data": [{"lineItem": "Revenue", "value": 5.0, "unit": "TWD"}]}
        """#
        let transport = FakeTransport([Self.income: (200, body)])

        await #expect(throws: Self.unreadable) {
            try await provider(transport).financialStatement(.income, for: aapl, period: nil)
        }
    }

    @Test func `a period with no lines has no data`() async throws {
        let body = #"{"fiscalYear": 2026, "fiscalPeriod": "Q3", "data": []}"#
        let transport = FakeTransport([Self.income: (200, body)])

        await #expect(throws: MarketDataError.noData) {
            try await provider(transport).financialStatement(.income, for: aapl, period: nil)
        }
    }

    @Test func `a period Equibles doesn't have has no data`() async throws {
        let transport = FakeTransport([Self.income: (404, Self.missing)])

        await #expect(throws: MarketDataError.noData) {
            try await provider(transport).financialStatement(.income, for: aapl, period: nil)
        }
    }

    @Test func `a fiscal period the app doesn't know is unavailable`() async throws {
        let body = #"""
        {"fiscalYear": 2026, "fiscalPeriod": "H1",
         "data": [{"lineItem": "Revenue", "value": 5.0, "unit": "USD"}]}
        """#
        let transport = FakeTransport([Self.income: (200, body)])

        await #expect(throws: Self.unreadable) {
            try await provider(transport).financialStatement(.income, for: aapl, period: nil)
        }
    }

    @Test func `no API key fails without a request`() async throws {
        let transport = FakeTransport()

        await #expect(throws: MarketDataError.missingAPIKey) {
            try await provider(transport, key: nil).financialStatement(.income, for: aapl, period: nil)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: [
        (401, MarketDataError.invalidAPIKey),
        (429, .dailyLimitReached),
        (503, .unavailable("Equibles answered with HTTP 503.")),
    ])
    func `a failing status becomes an error`(status: Int, expected: MarketDataError) async throws {
        let transport = FakeTransport([Self.income: (status, "")])

        await #expect(throws: expected) {
            try await provider(transport).financialStatement(.income, for: aapl, period: nil)
        }
    }

    @Test func `an unreadable body is unavailable`() async throws {
        let transport = FakeTransport([Self.income: (200, "<html>")])

        await #expect(throws: Self.unreadable) {
            try await provider(transport).financialStatement(.income, for: aapl, period: nil)
        }
    }

    private func provider(_ transport: FakeTransport, key: String? = "key") -> EquiblesResearchProvider {
        EquiblesResearchProvider(transport: transport, credentials: FakeCredentials(key))
    }
}
