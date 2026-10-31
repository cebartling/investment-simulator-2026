import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorMarketData
import Testing

struct EquiblesDividendsTests {
    let aapl: Ticker

    init() throws {
        aapl = try Ticker("AAPL")
    }

    static let path = "/v1/stocks/AAPL/dividends"

    /// As Equibles sent it on 2026-10-29 (`docs/spikes/PIN-413`), trimmed to
    /// two rows.
    static let apple = #"""
    {"data": [{"exDate": "2026-08-10", "amountPerShare": 0.27, "currency": "USD"},
              {"exDate": "2026-05-11", "amountPerShare": 0.27, "currency": "USD"}],
     "meta": {"limit": 2, "offset": 0, "count": 2, "hasMore": true}}
    """#

    /// A stock that pays no dividend, as AMZN is.
    static let none = #"""
    {"data": [], "meta": {"limit": 20, "offset": 0, "count": 0, "hasMore": false}}
    """#

    static let unknown = #"""
    {"error": {"code": "not_found", "message": "Stock 'ZZZZQ' not found.", "status": 404}}
    """#

    @Test func `each row becomes a dividend`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.apple)])

        let dividends = try await provider(transport).dividends(for: aapl)

        let amount = try #require(Decimal(string: "0.27"))
        #expect(dividends == [
            Dividend(exDate: "2026-08-10", amountPerShare: amount, currency: "USD"),
            Dividend(exDate: "2026-05-11", amountPerShare: amount, currency: "USD"),
        ])
    }

    @Test func `a sub-cent amount and another currency come through as sent`() async throws {
        let body = #"""
        {"data": [{"exDate": "2026-08-10", "amountPerShare": 0.0975, "currency": "CAD"}]}
        """#
        let transport = FakeTransport([Self.path: (200, body)])

        let dividends = try await provider(transport).dividends(for: aapl)

        #expect(try dividends == [
            Dividend(exDate: "2026-08-10", amountPerShare: #require(Decimal(string: "0.0975")), currency: "CAD"),
        ])
    }

    @Test func `one request reaches a weekly payer's whole year`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.apple)])

        _ = try await provider(transport, key: "eq_secret").dividends(for: aapl)

        #expect(transport.requests.count == 1)
        let request = try #require(transport.requests.first)
        #expect(request.url?.query() == "limit=60")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer eq_secret")
    }

    @Test func `a stock that pays no dividend has no data`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.none)])

        await #expect(throws: MarketDataError.noData) {
            try await provider(transport).dividends(for: aapl)
        }
    }

    @Test func `a ticker Equibles doesn't know has no data`() async throws {
        let transport = FakeTransport([Self.path: (404, Self.unknown)])

        await #expect(throws: MarketDataError.noData) {
            try await provider(transport).dividends(for: aapl)
        }
    }

    @Test func `no API key fails without a request`() async throws {
        let transport = FakeTransport()

        await #expect(throws: MarketDataError.missingAPIKey) {
            try await provider(transport, key: nil).dividends(for: aapl)
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
            try await provider(transport).dividends(for: aapl)
        }
    }

    @Test func `an unreadable body is unavailable`() async throws {
        let transport = FakeTransport([Self.path: (200, "<html>")])

        await #expect(throws: MarketDataError.unavailable("Equibles sent a response the app couldn't read.")) {
            try await provider(transport).dividends(for: aapl)
        }
    }

    private func provider(_ transport: FakeTransport, key: String? = "key") -> EquiblesResearchProvider {
        EquiblesResearchProvider(transport: transport, credentials: FakeCredentials(key))
    }
}
