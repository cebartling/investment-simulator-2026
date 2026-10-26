import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorMarketData
import Testing

struct EquiblesDailyPricesTests {
    let aapl: Ticker

    init() throws {
        aapl = try Ticker("AAPL")
    }

    static let path = "/v1/stocks/AAPL/prices"
    static let query = "startDate=2026-10-12&endDate=2026-10-25&limit=500"

    /// As Equibles sent it on 2026-10-25, trimmed to two sessions.
    static let twoSessions = #"""
    {"data": [{"date": "2026-10-23", "open": 349.1150, "high": 351.7300, "low": 345.7500, "close": 347.7250,
               "adjustedClose": 347.7250, "volume": 40152646},
              {"date": "2026-10-22", "open": 344.9400, "high": 348.3600, "low": 342.2800, "close": 348.2200,
               "adjustedClose": 348.2200, "volume": 46994081}],
     "meta": {"limit": 500, "offset": 0, "count": 2, "hasMore": false}}
    """#

    @Test func `bars keep their decimal digits exactly`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.twoSessions)])

        let bars = try await bars(transport)

        #expect(try bars == [
            DailyBar(sessionDate: "2026-10-23", open: decimal("349.115"), high: decimal("351.73"),
                     low: decimal("345.75"), close: decimal("347.725")),
            DailyBar(sessionDate: "2026-10-22", open: decimal("344.94"), high: decimal("348.36"),
                     low: decimal("342.28"), close: decimal("348.22")),
        ])
    }

    @Test func `request asks for the date range with the API key`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.twoSessions)])

        _ = try await bars(transport)

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.equibles.com\(Self.path)?\(Self.query)&offset=0")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer eq_test")
    }

    @Test func `later pages are fetched while more remain`() async throws {
        let first = Self.twoSessions.replacingOccurrences(of: #""hasMore": false"#, with: #""hasMore": true"#)
        let second = #"""
        {"data": [{"date": "2026-10-21", "open": 339.36, "high": 345.25, "low": 338.83, "close": 343.99}],
         "meta": {"limit": 500, "offset": 2, "count": 1, "hasMore": false}}
        """#
        let transport = FakeTransport([
            "\(Self.path)?\(Self.query)&offset=0": (200, first),
            "\(Self.path)?\(Self.query)&offset=2": (200, second),
        ])

        let bars = try await bars(transport)

        #expect(bars.map(\.sessionDate) == ["2026-10-23", "2026-10-22", "2026-10-21"])
        #expect(transport.requests.count == 2)
    }

    @Test func `an empty page that claims more is unreadable`() async {
        let empty = #"{"data": [], "meta": {"limit": 500, "offset": 0, "count": 0, "hasMore": true}}"#
        let transport = FakeTransport([Self.path: (200, empty)])

        await #expect(throws: QuoteError.unavailable("Equibles sent a response the app couldn't read.")) {
            try await bars(transport)
        }
        #expect(transport.requests.count == 1)
    }

    @Test func `paging stops after 20 pages that all claim more`() async {
        // As if Equibles ignored offset and sent the same page forever.
        let endless = Self.twoSessions.replacingOccurrences(of: #""hasMore": false"#, with: #""hasMore": true"#)
        let transport = FakeTransport([Self.path: (200, endless)])

        await #expect(throws: QuoteError.unavailable("Equibles sent a response the app couldn't read.")) {
            try await bars(transport)
        }
        #expect(transport.requests.count == 20)
    }

    @Test func `a bar outside its own range is unreadable`() async {
        let body = Self.twoSessions.replacingOccurrences(of: #""high": 351.7300"#, with: #""high": 340.0"#)
        let transport = FakeTransport([Self.path: (200, body)])

        await #expect(throws: QuoteError.unavailable("Equibles sent a response the app couldn't read.")) {
            try await bars(transport)
        }
    }

    @Test(arguments: [
        (401, QuoteError.invalidAPIKey),
        (429, .dailyLimitReached),
        (503, .unavailable("Equibles answered with HTTP 503.")),
    ])
    func `errors are mapped`(status: Int, error: QuoteError) async {
        let transport = FakeTransport([Self.path: (status, "")])

        await #expect(throws: error) {
            try await bars(transport)
        }
    }

    @Test func `ticker with no prices is unknown`() async {
        let transport = FakeTransport([Self.path: (404, "")])

        await #expect(throws: QuoteError.unknownTicker(aapl)) {
            try await bars(transport)
        }
    }

    @Test func `missing API key fails without a request`() async {
        let transport = FakeTransport()

        await #expect(throws: QuoteError.missingAPIKey) {
            try await bars(transport, key: nil)
        }
        #expect(transport.requests.isEmpty)
    }

    private func bars(_ transport: FakeTransport, key: String? = "eq_test") async throws -> [DailyBar] {
        try await EquiblesQuoteProvider(transport: transport, credentials: FakeCredentials(key))
            .dailyBars(for: aapl, from: "2026-10-12", through: "2026-10-25")
    }

    private func decimal(_ text: String) throws -> Decimal {
        try #require(Decimal(string: text))
    }
}
