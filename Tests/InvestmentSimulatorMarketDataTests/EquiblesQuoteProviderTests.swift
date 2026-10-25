import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorMarketData
import Testing

struct EquiblesQuoteProviderTests {
    let vti: Ticker

    init() throws {
        vti = try Ticker("VTI")
    }

    static let liveQuote = #"""
    {"ticker": "VTI", "price": 316.9961, "bidPrice": 316.98, "askPrice": 317.0,
     "asOf": "2026-08-31T23:59:55.8589413Z", "sessionDate": "2026-08-31",
     "expectedSessionDate": "2026-08-31", "stale": false, "ageSeconds": 25176,
     "source": "Rest", "delayed": true}
    """#

    static let latestClose = #"""
    {"data": [{"ticker": "VTI", "date": "2026-08-07", "close": 223.96, "adjustedClose": 223.96,
               "volume": 105473700}], "notFound": []}
    """#

    @Test func `live quote is the price`() async throws {
        let transport = FakeTransport(["/v1/stocks/VTI/quote": (200, Self.liveQuote)])

        let quote = try await provider(transport).quote(for: vti)

        #expect(try quote.price == #require(Decimal(string: "316.9961")))
        #expect(quote.source == .liveQuote(delayed: true))
        #expect(quote.ticker == vti)
        let asOf = try #require(ISO8601DateFormatter().date(from: "2026-08-31T23:59:55Z")).addingTimeInterval(0.8589413)
        #expect(abs(quote.asOf.timeIntervalSince(asOf)) < 0.001)
    }

    @Test func `request carries the API key as a bearer token`() async throws {
        let transport = FakeTransport(["/v1/stocks/VTI/quote": (200, Self.liveQuote)])

        _ = try await provider(transport, key: "eq_secret").quote(for: vti)

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.equibles.com/v1/stocks/VTI/quote")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer eq_secret")
        #expect(request.httpMethod == "GET")
    }

    @Test func `free plan falls back to the latest close`() async throws {
        let transport = FakeTransport([
            "/v1/stocks/VTI/quote": (403, #"{"error": "forbidden"}"#),
            "/v1/prices/latest": (200, Self.latestClose),
        ])

        let quote = try await provider(transport).quote(for: vti)

        #expect(try quote.price == #require(Decimal(string: "223.96")))
        #expect(quote.source == .close(sessionDate: "2026-08-07"))
        #expect(transport.requests.last?.url?.absoluteString == "https://api.equibles.com/v1/prices/latest?tickers=VTI")
    }

    @Test func `a close is dated at 4 PM New York on its session`() async throws {
        let transport = FakeTransport([
            "/v1/stocks/VTI/quote": (403, ""),
            "/v1/prices/latest": (200, Self.latestClose),
        ])

        let quote = try await provider(transport).quote(for: vti)

        // 2026-08-07 16:00 EDT is 20:00 UTC.
        #expect(try quote.asOf == #require(ISO8601DateFormatter().date(from: "2026-08-07T20:00:00Z")))
    }

    @Test func `stale live quote falls back to the latest close`() async throws {
        let stale = Self.liveQuote.replacingOccurrences(of: #""stale": false"#, with: #""stale": true"#)
        let transport = FakeTransport([
            "/v1/stocks/VTI/quote": (200, stale),
            "/v1/prices/latest": (200, Self.latestClose),
        ])

        let quote = try await provider(transport).quote(for: vti)

        #expect(quote.source == .close(sessionDate: "2026-08-07"))
    }

    @Test(arguments: ["316.9961", "0.0001", "123456.7", "250", "0.1", "99.99"])
    func `prices keep their decimal digits exactly`(price: String) async throws {
        let body = Self.liveQuote.replacingOccurrences(of: "316.9961", with: price)
        let transport = FakeTransport(["/v1/stocks/VTI/quote": (200, body)])

        let quote = try await provider(transport).quote(for: vti)

        #expect(try quote.price == #require(Decimal(string: price)))
    }

    @Test func `missing API key fails without a request`() async {
        let transport = FakeTransport()

        await #expect(throws: QuoteError.missingAPIKey) {
            try await provider(transport, key: nil).quote(for: vti)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func `blank API key counts as missing`() async {
        await #expect(throws: QuoteError.missingAPIKey) {
            try await provider(FakeTransport(), key: "  ").quote(for: vti)
        }
    }

    @Test(arguments: [
        (401, QuoteError.invalidAPIKey),
        (429, .dailyLimitReached),
        (503, .unavailable("Equibles answered with HTTP 503.")),
    ])
    func `quote errors are mapped`(status: Int, error: QuoteError) async {
        let transport = FakeTransport(["/v1/stocks/VTI/quote": (status, "")])

        await #expect(throws: error) {
            try await provider(transport).quote(for: vti)
        }
    }

    @Test func `ticker with no quote is unknown`() async {
        let transport = FakeTransport(["/v1/stocks/VTI/quote": (404, "")])

        await #expect(throws: QuoteError.unknownTicker(vti)) {
            try await provider(transport).quote(for: vti)
        }
    }

    @Test func `ticker missing from the latest closes is unknown`() async {
        let transport = FakeTransport([
            "/v1/stocks/VTI/quote": (403, ""),
            "/v1/prices/latest": (200, #"{"data": [], "notFound": ["VTI"]}"#),
        ])

        await #expect(throws: QuoteError.unknownTicker(vti)) {
            try await provider(transport).quote(for: vti)
        }
    }

    @Test func `daily limit on the close request is reported`() async {
        let transport = FakeTransport([
            "/v1/stocks/VTI/quote": (403, ""),
            "/v1/prices/latest": (429, ""),
        ])

        await #expect(throws: QuoteError.dailyLimitReached) {
            try await provider(transport).quote(for: vti)
        }
    }

    @Test func `unexpected response body is unavailable`() async {
        let transport = FakeTransport(["/v1/stocks/VTI/quote": (200, "<html>")])

        await #expect(throws: QuoteError.unavailable("Equibles sent a response the app couldn't read.")) {
            try await provider(transport).quote(for: vti)
        }
    }

    @Test func `network failure is unavailable`() async {
        let transport = FakeTransport(failure: URLError(.notConnectedToInternet))

        await #expect(throws: QuoteError.unavailable("Couldn't reach Equibles.")) {
            try await provider(transport).quote(for: vti)
        }
    }

    @Test(arguments: [
        (QuoteError.missingAPIKey, "Add your Equibles API key in Settings to get prices."),
        (.invalidAPIKey, "Equibles didn't accept the API key. Check it in Settings."),
        (.dailyLimitReached, "You've reached today's Equibles request limit. It resets at midnight UTC."),
        (.unavailable("Couldn't reach Equibles."), "Couldn't get a price. Couldn't reach Equibles."),
    ])
    func `quote errors describe the problem`(error: QuoteError, description: String) {
        #expect(error.localizedDescription == description)
    }

    @Test func `unknown ticker error names the ticker`() throws {
        let error = try QuoteError.unknownTicker(Ticker("ZZZZ"))

        #expect(error.localizedDescription == "Equibles has no price for ZZZZ.")
    }

    private func provider(_ transport: FakeTransport, key: String? = "eq_test") -> EquiblesQuoteProvider {
        EquiblesQuoteProvider(transport: transport, credentials: FakeCredentials(key))
    }
}
