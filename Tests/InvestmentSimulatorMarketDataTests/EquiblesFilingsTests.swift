import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorMarketData
import Testing

struct EquiblesFilingsTests {
    let aapl: Ticker

    init() throws {
        aapl = try Ticker("AAPL")
    }

    static let path = "/v1/stocks/AAPL/filings"
    static let unreadable = MarketDataError.unavailable("Equibles sent a response the app couldn't read.")

    static let recordedURL = "https://equibles.com/stocks/aapl/documents/dd7d5e88-69c1-4130-9da8-58bacc4b9d96"

    /// As Equibles sent it (`docs/spikes/PIN-413/equibles/filings-AAPL.json`).
    static let recordedFiling = #"""
    {"id": "dd7d5e88-69c1-4130-9da8-58bacc4b9d96", "ticker": "AAPL", "companyName": "Apple Inc.",
     "documentType": "TenQ", "documentTypeName": "10-Q", "filedDate": "2026-07-31", "summary": null,
     "reportingForDate": "2026-06-27", "itemNumbers": [], "lineCount": 1207,
     "accessionNumber": "0000320193-26-000020", "acceptedAt": null,
     "ingestedAt": "2026-07-31T10:12:55.276575Z", "url": "\#(recordedURL)"}
    """#

    /// As Equibles sent it, from the same page. A transcript has no
    /// accession number.
    static let recordedTranscript = #"""
    {"id": "2a43f09c-d782-4787-89b8-bc8365d8521f", "ticker": "AAPL", "companyName": "Apple Inc.",
     "documentType": "EarningsCallTranscript", "documentTypeName": "Earnings Call", "filedDate": "2026-07-30",
     "summary": null, "reportingForDate": "2026-06-30", "itemNumbers": [], "lineCount": 187,
     "accessionNumber": null, "acceptedAt": null, "ingestedAt": "2026-08-06T00:27:11.159048Z",
     "url": "https://equibles.com/stocks/aapl/documents/2a43f09c-d782-4787-89b8-bc8365d8521f"}
    """#

    static func row(
        _ type: String,
        _ name: String,
        filed: String = "2026-07-31",
        reporting: String? = "2026-06-27",
        url: String = "https://equibles.com/stocks/aapl/documents/1",
    ) -> String {
        let reportingForDate = reporting.map { "\"\($0)\"" } ?? "null"
        return #"""
        {"documentType": "\#(type)", "documentTypeName": "\#(name)", "filedDate": "\#(filed)",
         "reportingForDate": \#(reportingForDate), "url": "\#(url)"}
        """#
    }

    static func body(_ rows: String...) -> String {
        #"{"data": [\#(rows.joined(separator: ","))], "meta": {"limit": 50, "offset": 0}}"#
    }

    @Test func `a row becomes a filing`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.body(Self.row("TenQ", "10-Q")))])

        let filings = try await provider(transport).filings(for: aapl)

        #expect(try filings == [
            Filing(
                form: "10-Q",
                filedDate: "2026-07-31",
                reportingForDate: "2026-06-27",
                url: #require(URL(string: "https://equibles.com/stocks/aapl/documents/1")),
            ),
        ])
    }

    @Test func `rows as Equibles sends them are read`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.body(Self.recordedFiling, Self.recordedTranscript))])

        let filings = try await provider(transport).filings(for: aapl)

        #expect(try filings == [
            Filing(
                form: "10-Q",
                filedDate: "2026-07-31",
                reportingForDate: "2026-06-27",
                url: #require(URL(string: Self.recordedURL)),
            ),
        ])
    }

    @Test func `only 10-K, 10-Q and 8-K filings are kept`() async throws {
        let body = Self.body(
            Self.row("TenK", "10-K"),
            Self.row("TenQ", "10-Q"),
            Self.row("EightK", "8-K"),
            Self.row("EightKa", "8-K/A"),
            Self.row("EarningsCallTranscript", "Earnings Call Transcript"),
            Self.row("Def14A", "DEF 14A"),
        )
        let transport = FakeTransport([Self.path: (200, body)])

        let filings = try await provider(transport).filings(for: aapl)

        #expect(filings.map(\.form) == ["10-K", "10-Q", "8-K"])
    }

    @Test func `a filing can have no reporting date`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.body(Self.row("EightK", "8-K", reporting: nil)))])

        let filings = try await provider(transport).filings(for: aapl)

        #expect(filings.first?.reportingForDate == nil)
    }

    @Test func `a row left out can't spoil the rest`() async throws {
        let transcript = #"{"documentType": "Other", "documentTypeName": null, "filedDate": null, "url": null}"#
        let transport = FakeTransport([Self.path: (200, Self.body(Self.row("TenK", "10-K"), transcript))])

        let filings = try await provider(transport).filings(for: aapl)

        #expect(filings.map(\.form) == ["10-K"])
    }

    @Test func `one request asks for fifty rows with the saved key`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.body(Self.row("TenK", "10-K")))])

        _ = try await provider(transport, key: "eq_secret").filings(for: aapl)

        #expect(transport.requests.count == 1)
        let request = try #require(transport.requests.first)
        #expect(request.url?.query() == "limit=50")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer eq_secret")
    }

    @Test(arguments: [
        body(),
        body(row("Def14A", "DEF 14A")),
    ])
    func `no matching filings is no data`(body: String) async throws {
        let transport = FakeTransport([Self.path: (200, body)])

        await #expect(throws: MarketDataError.noData) {
            try await provider(transport).filings(for: aapl)
        }
    }

    @Test func `a ticker Equibles doesn't know has no data`() async throws {
        let transport = FakeTransport([Self.path: (404, "")])

        await #expect(throws: MarketDataError.noData) {
            try await provider(transport).filings(for: aapl)
        }
    }

    @Test func `a filing date that isn't a date is unavailable`() async throws {
        let transport = FakeTransport([Self.path: (200, Self.body(Self.row("TenK", "10-K", filed: "soon")))])

        await #expect(throws: Self.unreadable) {
            try await provider(transport).filings(for: aapl)
        }
    }

    @Test func `a kept row with no url is unavailable`() async throws {
        let row = #"{"documentType": "TenK", "documentTypeName": "10-K", "filedDate": "2026-07-31", "url": null}"#
        let transport = FakeTransport([Self.path: (200, Self.body(row))])

        await #expect(throws: Self.unreadable) {
            try await provider(transport).filings(for: aapl)
        }
    }

    @Test func `a link that can't open in a browser is unavailable`() async throws {
        let body = Self.body(Self.row("TenK", "10-K", url: "file:///etc/hosts"))
        let transport = FakeTransport([Self.path: (200, body)])

        await #expect(throws: Self.unreadable) {
            try await provider(transport).filings(for: aapl)
        }
    }

    private func provider(_ transport: FakeTransport, key: String? = "key") -> EquiblesResearchProvider {
        EquiblesResearchProvider(transport: transport, credentials: FakeCredentials(key))
    }
}
