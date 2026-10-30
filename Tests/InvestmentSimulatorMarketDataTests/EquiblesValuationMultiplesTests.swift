import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorMarketData
import Testing

struct EquiblesValuationMultiplesTests {
    let aapl: Ticker

    init() throws {
        aapl = try Ticker("AAPL")
    }

    static let path = "/v1/stocks/AAPL/valuation-multiples"

    /// As Equibles sent it on 2026-10-29 (`docs/spikes/PIN-413`), trimmed to
    /// the fields the multiples read. P/E and EV/EBIT have too few peers for
    /// a median.
    static let apple = #"""
    {"ticker": "AAPL", "companyName": "Apple Inc.", "industry": "Consumer Electronics",
     "marketCap": 5024265535488.0, "evToRevenue": 10.81, "evToEbit": 32.57, "peRatio": 39.53,
     "industryContext": {"industry": "Consumer Electronics", "companyCount": 18,
       "evToRevenueMedian": 0.5, "evToRevenueP25": 0.28, "evToRevenueP75": 1.1,
       "evToEbitMedian": null, "evToEbitP25": null, "evToEbitP75": null,
       "peMedian": null, "peP25": null, "peP75": null}}
    """#

    /// A `404` for a company with no computable ratio. VTI's real answer
    /// names another ticker, so the text says nothing reliable.
    static let noRatio = #"""
    {"error": {"code": "not_found", "message": "VB has no computable valuation multiple.", "status": 404}}
    """#

    static let unknown = #"""
    {"error": {"code": "not_found", "message": "Stock 'ZZZZQ' not found.", "status": 404}}
    """#

    @Test func `ratios and peer figures keep their decimal digits`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.apple)])

        let multiples = try await provider(transport).valuationMultiples(for: aapl)

        #expect(try multiples.evToRevenue == ValuationRatio(
            value: decimal("10.81"),
            peerMedian: decimal("0.5"),
            peerP25: decimal("0.28"),
            peerP75: decimal("1.1"),
        ))
    }

    @Test func `a null median or quartile stays nil`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.apple)])

        let multiples = try await provider(transport).valuationMultiples(for: aapl)

        #expect(try multiples.peRatio == ValuationRatio(
            value: decimal("39.53"),
            peerMedian: nil,
            peerP25: nil,
            peerP75: nil,
        ))
        #expect(try multiples.evToEbit.value == decimal("32.57"))
        #expect(multiples.evToEbit.peerMedian == nil)
    }

    @Test func `each ratio reads its own peer figures`() async throws {
        let body = #"""
        {"peRatio": 1, "evToRevenue": 2, "evToEbit": 3,
         "industryContext": {"peMedian": 11, "peP25": 12, "peP75": 13,
           "evToRevenueMedian": 21, "evToRevenueP25": 22, "evToRevenueP75": 23,
           "evToEbitMedian": 31, "evToEbitP25": 32, "evToEbitP75": 33}}
        """#
        let transport = FakeTransport([Self.path: (200, body)])

        let multiples = try await provider(transport).valuationMultiples(for: aapl)

        #expect(multiples == ValuationMultiples(
            peRatio: ValuationRatio(value: 1, peerMedian: 11, peerP25: 12, peerP75: 13),
            evToRevenue: ValuationRatio(value: 2, peerMedian: 21, peerP25: 22, peerP75: 23),
            evToEbit: ValuationRatio(value: 3, peerMedian: 31, peerP25: 32, peerP75: 33),
        ))
    }

    @Test func `a null ratio stays nil`() async throws {
        let body = #"{"evToRevenue": null, "evToEbit": null, "peRatio": null, "industryContext": null}"#
        let transport = FakeTransport([Self.path: (200, body)])

        let multiples = try await provider(transport).valuationMultiples(for: aapl)

        let none = ValuationRatio(value: nil, peerMedian: nil, peerP25: nil, peerP75: nil)
        #expect(multiples == ValuationMultiples(peRatio: none, evToRevenue: none, evToEbit: none))
    }

    @Test(arguments: [Self.noRatio, Self.unknown])
    func `every 404 has no data`(body: String) async throws {
        let transport = FakeTransport([Self.path: (404, body)])

        await #expect(throws: MarketDataError.noData) {
            try await provider(transport).valuationMultiples(for: aapl)
        }
    }

    @Test func `it sends the API key`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.apple)])

        _ = try await provider(transport, key: "eq_secret").valuationMultiples(for: aapl)

        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer eq_secret")
    }

    @Test func `no API key fails without a request`() async throws {
        let transport = FakeTransport()

        await #expect(throws: MarketDataError.missingAPIKey) {
            try await provider(transport, key: nil).valuationMultiples(for: aapl)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: [
        (401, MarketDataError.invalidAPIKey),
        (429, .dailyLimitReached),
        (503, .unavailable("Equibles answered with HTTP 503.")),
    ])
    func `a failing status becomes an error`(status: Int, expected: MarketDataError) async throws {
        let transport = FakeTransport([Self.path: (status, "")])

        await #expect(throws: expected) {
            try await provider(transport).valuationMultiples(for: aapl)
        }
    }

    @Test func `an unreadable body is unavailable`() async throws {
        let transport = FakeTransport([Self.path: (200, "<html>")])

        await #expect(throws: MarketDataError.unavailable("Equibles sent a response the app couldn't read.")) {
            try await provider(transport).valuationMultiples(for: aapl)
        }
    }

    private func decimal(_ text: String) throws -> Decimal {
        try #require(Decimal(string: text))
    }

    private func provider(_ transport: FakeTransport, key: String? = "key") -> EquiblesResearchProvider {
        EquiblesResearchProvider(transport: transport, credentials: FakeCredentials(key))
    }
}
