import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorMarketData
import Testing

struct EquiblesCompanyProfileTests {
    let aapl: Ticker

    init() throws {
        aapl = try Ticker("AAPL")
    }

    static let path = "/v1/screener/stocks"

    /// As Equibles sent it on 2026-10-29 (`docs/spikes/PIN-413`), trimmed to
    /// the fields the profile reads.
    static let apple = #"""
    {"totalCount": 1, "count": 1, "page": 1, "totalPages": 1, "notFound": [],
     "data": [{"ticker": "AAPL", "name": "Apple Inc.", "market": "US", "currency": "USD",
               "sector": "Technology", "industry": "Consumer Electronics",
               "marketCap": 5024265535488.0, "price": 343.83}]}
    """#

    static let unknown = #"""
    {"totalCount": 0, "count": 0, "page": 1, "totalPages": 1, "notFound": ["ZZZZQ"], "data": []}
    """#

    @Test func `the profile comes from the screener row`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.apple)])

        let profile = try await provider(transport).companyProfile(for: aapl)

        #expect(profile == CompanyProfile(
            name: "Apple Inc.",
            sector: "Technology",
            industry: "Consumer Electronics",
            marketCap: Money(5_024_265_535_488),
        ))
    }

    @Test func `it asks for the one ticker with the API key`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.apple)])

        _ = try await provider(transport, key: "eq_secret").companyProfile(for: aapl)

        let request = try #require(transport.requests.first)
        #expect(request.url?.query() == "tickers=AAPL")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer eq_secret")
    }

    @Test func `a missing sector, industry or market cap stays nil`() async throws {
        let body = #"{"data": [{"ticker": "AAPL", "name": "Apple Inc.", "sector": null, "industry": null, "marketCap": null}]}"#
        let transport = FakeTransport([Self.path: (200, body)])

        let profile = try await provider(transport).companyProfile(for: aapl)

        #expect(profile == CompanyProfile(name: "Apple Inc.", sector: nil, industry: nil, marketCap: nil))
    }

    @Test func `a ticker the screener doesn't know has no data`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.unknown)])

        await #expect(throws: MarketDataError.noData) {
            try await provider(transport).companyProfile(for: aapl)
        }
    }

    @Test func `no API key fails without a request`() async throws {
        let transport = FakeTransport()

        await #expect(throws: MarketDataError.missingAPIKey) {
            try await provider(transport, key: nil).companyProfile(for: aapl)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: [
        (401, MarketDataError.invalidAPIKey),
        (404, .noData),
        (429, .dailyLimitReached),
        (503, .unavailable("Equibles answered with HTTP 503.")),
    ])
    func `a failing status becomes an error`(status: Int, expected: MarketDataError) async throws {
        let transport = FakeTransport([Self.path: (status, "")])

        await #expect(throws: expected) {
            try await provider(transport).companyProfile(for: aapl)
        }
    }

    @Test func `an unreadable body is unavailable`() async throws {
        let transport = FakeTransport([Self.path: (200, "<html>")])

        await #expect(throws: MarketDataError.unavailable("Equibles sent a response the app couldn't read.")) {
            try await provider(transport).companyProfile(for: aapl)
        }
    }

    @Test func `an unreachable server is unavailable`() async throws {
        let transport = FakeTransport(failure: URLError(.notConnectedToInternet))

        await #expect(throws: MarketDataError.unavailable("Couldn't reach Equibles.")) {
            try await provider(transport).companyProfile(for: aapl)
        }
    }

    private func provider(_ transport: FakeTransport, key: String? = "key") -> EquiblesResearchProvider {
        EquiblesResearchProvider(transport: transport, credentials: FakeCredentials(key))
    }
}
