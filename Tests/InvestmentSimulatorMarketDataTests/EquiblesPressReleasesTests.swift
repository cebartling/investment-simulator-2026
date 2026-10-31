import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorMarketData
import Testing

struct EquiblesPressReleasesTests {
    let plug: Ticker

    init() throws {
        plug = try Ticker("PLUG")
    }

    static let path = "/v1/stocks/PLUG/ir-news"
    static let unreadable = MarketDataError.unavailable("Equibles sent a response the app couldn't read.")

    static let releaseURL = "https://www.ir.plugpower.com/press-releases/news-details/2026/lead/default.aspx"

    /// Shaped as Equibles sent it on 2026-10-29 (`docs/spikes/PIN-413`),
    /// trimmed to one row with a shorter title and link.
    static let plugPower = #"""
    {"coverage": {"status": "scraped", "lastScrapedAt": "2026-10-29T11:04:13.49419Z"},
     "data": [{"publishedAt": "2026-10-19T11:00:00Z",
               "title": "Plug Power Appoints a Lead",
               "url": "\#(releaseURL)",
               "summary": null}],
     "meta": {"limit": 5, "offset": 0, "count": 1, "hasMore": true}}
    """#

    static func body(
        status: String,
        publishedAt: String = "2026-10-19T11:00:00Z",
        url: String = "https://x.test/a",
    ) -> String {
        #"""
        {"coverage": {"status": "\#(status)", "lastScrapedAt": null},
         "data": [{"publishedAt": "\#(publishedAt)", "title": "A", "url": "\#(url)", "summary": "Why"}]}
        """#
    }

    @Test func `each row becomes a press release`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.plugPower)])

        let result = try await provider(transport).pressReleases(for: plug)

        #expect(result.coverage == .scraped)
        #expect(try result.releases == [
            PressRelease(
                publishedAt: #require(ISO8601DateFormatter().date(from: "2026-10-19T11:00:00Z")),
                title: "Plug Power Appoints a Lead",
                url: #require(URL(string: Self.releaseURL)),
                summary: nil,
            ),
        ])
    }

    @Test func `a summary comes through`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.body(status: "scraped"))])

        let result = try await provider(transport).pressReleases(for: plug)

        #expect(result.releases.first?.summary == "Why")
    }

    @Test func `a date can have fractional seconds`() async throws {
        let body = Self.body(status: "scraped", publishedAt: "2026-10-19T11:00:00.000Z")
        let transport = FakeTransport([Self.path: (200, body)])

        let result = try await provider(transport).pressReleases(for: plug)

        #expect(result.releases.first?.publishedAt == ISO8601DateFormatter().date(from: "2026-10-19T11:00:00Z"))
    }

    @Test(arguments: [
        ("scraped", PressReleaseCoverage.scraped),
        ("attempted", .attempted),
        ("discovered", .discovered),
        ("none", .untracked),
    ])
    func `each coverage status comes through without rows`(
        status: String,
        expected: PressReleaseCoverage,
    ) async throws {
        let body = #"{"coverage": {"status": "\#(status)", "lastScrapedAt": null}, "data": []}"#
        let transport = FakeTransport([Self.path: (200, body)])

        let result = try await provider(transport).pressReleases(for: plug)

        #expect(result.coverage == expected)
        #expect(result.releases.isEmpty)
    }

    @Test func `it asks for the first page with the saved key`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.plugPower)])

        _ = try await provider(transport, key: "eq_secret").pressReleases(for: plug)

        #expect(transport.requests.count == 1)
        let request = try #require(transport.requests.first)
        #expect(request.url?.query() == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer eq_secret")
    }

    @Test func `a ticker Equibles doesn't know has no data`() async throws {
        let transport = FakeTransport([Self.path: (404, "")])

        await #expect(throws: MarketDataError.noData) {
            try await provider(transport).pressReleases(for: plug)
        }
    }

    @Test func `no API key fails without a request`() async throws {
        let transport = FakeTransport()

        await #expect(throws: MarketDataError.missingAPIKey) {
            try await provider(transport, key: nil).pressReleases(for: plug)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func `an unknown coverage status keeps its rows and reads as untracked`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.body(status: "pending"))])

        let result = try await provider(transport).pressReleases(for: plug)

        #expect(result.coverage == .untracked)
        #expect(result.releases.count == 1)
    }

    @Test(arguments: [
        #"{"publishedAt": "soon", "title": "A", "url": "https://x.test/a"}"#,
        #"{"publishedAt": null, "title": "A", "url": "https://x.test/a"}"#,
        #"{"publishedAt": "2026-10-19T11:00:00Z", "title": null, "url": "https://x.test/a"}"#,
        #"{"publishedAt": "2026-10-19T11:00:00Z", "title": "A", "url": "/news/a"}"#,
        #"{"publishedAt": "2026-10-19T11:00:00Z", "title": "A", "url": "file:///etc/hosts"}"#,
        #"{"publishedAt": "2026-10-19T11:00:00Z", "title": "A", "url": null}"#,
    ])
    func `a row that can't be read is left out`(row: String) async throws {
        let good = #"{"publishedAt": "2026-10-19T11:00:00Z", "title": "Good", "url": "https://x.test/good"}"#
        let body = #"{"coverage": {"status": "scraped"}, "data": [\#(row), \#(good)]}"#
        let transport = FakeTransport([Self.path: (200, body)])

        let result = try await provider(transport).pressReleases(for: plug)

        #expect(result.releases.map(\.title) == ["Good"])
    }

    @Test func `no readable rows is unavailable, not none published`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.body(status: "scraped", publishedAt: "soon"))])

        await #expect(throws: Self.unreadable) {
            try await provider(transport).pressReleases(for: plug)
        }
    }

    @Test(arguments: ["file:///etc/hosts", "javascript:alert(1)", "not a link"])
    func `a lone link that can't open in a browser is unavailable`(url: String) async throws {
        let transport = FakeTransport([Self.path: (200, Self.body(status: "scraped", url: url))])

        await #expect(throws: Self.unreadable) {
            try await provider(transport).pressReleases(for: plug)
        }
    }

    private func provider(_ transport: FakeTransport, key: String? = "key") -> EquiblesResearchProvider {
        EquiblesResearchProvider(transport: transport, credentials: FakeCredentials(key))
    }
}
