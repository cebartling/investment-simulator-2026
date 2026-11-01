import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorMarketData
import Testing

struct EdgarSecurityDirectoryTests {
    static let path = "/files/company_tickers_exchange.json"

    /// As SEC EDGAR sent it on 2026-10-29 (`docs/spikes/PIN-413/edgar`),
    /// trimmed to a few rows. The last has a `null` exchange, as some do.
    static let list = #"""
    {"fields": ["cik", "name", "ticker", "exchange"],
     "data": [[320193, "Apple Inc.", "AAPL", "Nasdaq"],
              [789019, "MICROSOFT CORP", "MSFT", "Nasdaq"],
              [1067983, "BERKSHIRE HATHAWAY INC", "BRK-B", "NYSE"],
              [99, "Unlisted Trust", "UNLT", null]]}
    """#

    private func directory(
        _ transport: FakeTransport,
        email: String? = "me@example.com",
    ) -> EdgarSecurityDirectory {
        EdgarSecurityDirectory(transport: transport, contactEmails: FakeContactEmail(email))
    }

    @Test func `search finds a company by name`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.list)])

        let results = try await directory(transport).search("apple")

        #expect(try results == [ListedSecurity(ticker: Ticker("AAPL"), name: "Apple Inc.", exchange: "Nasdaq")])
    }

    @Test func `a lookup finds a share class by either spelling`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.list)])

        let found = try await directory(transport).security(for: Ticker("BRK.B"))

        #expect(found?.exchange == "NYSE")
    }

    @Test func `a lookup of a ticker EDGAR lacks finds nothing`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.list)])

        #expect(try await directory(transport).security(for: Ticker("VTI")) == nil)
    }

    @Test func `a row can have no exchange`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.list)])

        let found = try await directory(transport).security(for: Ticker("UNLT"))

        #expect(found?.name == "Unlisted Trust")
        #expect(found?.exchange == nil)
    }

    @Test func `a row with an unusable symbol is skipped`() async throws {
        let list = #"""
        {"fields": ["cik", "name", "ticker", "exchange"],
         "data": [[1, "Odd Co", "A B", "NYSE"], [2, "No Symbol Co", null, "NYSE"],
                  [320193, "Apple Inc.", "AAPL", "Nasdaq"]]}
        """#
        let transport = FakeTransport([Self.path: (200, list)])

        let found = try await directory(transport).search("co")

        #expect(found.isEmpty)
        #expect(try await directory(transport).security(for: Ticker("AAPL")) != nil)
    }

    @Test func `every request names the contact email`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.list)])

        _ = try await directory(transport, email: "me@example.com").search("apple")

        let request = try #require(transport.requests.first)
        #expect(request.url?.host() == "www.sec.gov")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Investment Simulator me@example.com")
    }

    @Test func `the list downloads once`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.list)])
        let directory = directory(transport)

        _ = try await directory.search("apple")
        _ = try await directory.security(for: Ticker("MSFT"))

        #expect(transport.requests.count == 1)
    }

    @Test func `calls at the same time share one download`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.list)])
        let directory = directory(transport)

        async let first = directory.search("apple")
        async let second = directory.search("microsoft")
        async let third = directory.security(for: Ticker("MSFT"))
        _ = try await (first, second, third)

        #expect(transport.requests.count == 1)
    }

    @Test func `no contact email sends nothing`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.list)])

        await #expect(throws: MarketDataError.missingContactEmail) {
            try await directory(transport, email: nil).search("apple")
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func `an email saved after a failure works without a restart`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.list)])
        let emails = FakeContactEmail(nil)
        let directory = EdgarSecurityDirectory(transport: transport, contactEmails: emails)
        await #expect(throws: MarketDataError.missingContactEmail) {
            try await directory.search("apple")
        }

        try emails.setContactEmail("me@example.com")

        #expect(try await directory.search("apple").count == 1)
    }

    @Test func `an unreadable contact email is reported, not treated as missing`() async throws {
        let directory = EdgarSecurityDirectory(
            transport: FakeTransport(),
            contactEmails: FakeContactEmail(nil, failsToRead: true),
        )

        await #expect {
            try await directory.search("apple")
        } throws: { error in
            guard case let .unavailable(detail) = error as? MarketDataError else {
                return false
            }
            return detail.contains("contact email")
        }
    }

    @Test(arguments: [403, 429, 500])
    func `a refused download is unavailable`(status: Int) async {
        let transport = FakeTransport([Self.path: (status, "")])

        await #expect(throws: MarketDataError.unavailable("SEC EDGAR answered with HTTP \(status).")) {
            try await directory(transport).search("apple")
        }
    }

    @Test func `an unreachable EDGAR is unavailable`() async {
        let transport = FakeTransport(failure: URLError(.notConnectedToInternet))

        await #expect(throws: MarketDataError.unavailable("Couldn't reach SEC EDGAR.")) {
            try await directory(transport).search("apple")
        }
    }

    @Test func `an unreadable list is unavailable`() async {
        let transport = FakeTransport([Self.path: (200, "<html>")])

        await #expect(throws: MarketDataError.unavailable("SEC EDGAR sent a response the app couldn't read.")) {
            try await directory(transport).search("apple")
        }
    }

    @Test func `a failed download isn't kept`() async throws {
        let failing = FakeTransport([Self.path: (500, "")])
        let directory = directory(failing)

        await #expect(throws: MarketDataError.self) {
            try await directory.search("apple")
        }
        await #expect(throws: MarketDataError.self) {
            try await directory.search("apple")
        }

        #expect(failing.requests.count == 2)
    }

    @Test func `the missing email error points to Settings`() {
        #expect(MarketDataError.missingContactEmail.localizedDescription.contains("Settings"))
    }
}
