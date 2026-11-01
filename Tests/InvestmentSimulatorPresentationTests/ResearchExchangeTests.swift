import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct ResearchExchangeTests {
    private func tab(
        _ symbol: String,
        _ listing: Result<[ListedSecurity], MarketDataError>,
    ) async throws -> ResearchTabModel {
        let ticker = try Ticker(symbol)
        let tab = try ResearchTabModel(
            ticker: ticker,
            quotes: FakeQuotes(.success(makeQuote(ticker: symbol, price: 12))),
            dailyPrices: FakeDailyPrices(),
            ports: FakeResearchData(directory: FakeDirectory(listing)).ports,
            clock: Date.init,
        )
        await tab.load()
        return tab
    }

    private func listing(exchange: String?) throws -> [ListedSecurity] {
        try [ListedSecurity(ticker: Ticker("BRK-B"), name: "Berkshire", exchange: exchange)]
    }

    @Test func `a tab loads its exchange, however the share class is spelled`() async throws {
        let tab = try await tab("BRK.B", .success(listing(exchange: "NYSE")))

        #expect(tab.exchangeState == .loaded("NYSE"))
        #expect(tab.exchangeMessage == nil)
    }

    @Test func `a ticker EDGAR lacks has no exchange and no complaint`() async throws {
        let tab = try await tab("VTI", .success(listing(exchange: "NYSE")))

        #expect(tab.exchangeState == .empty(.noData))
        #expect(tab.exchangeMessage == nil)
    }

    @Test func `a listing with no exchange shows none`() async throws {
        let tab = try await tab("BRK-B", .success(listing(exchange: nil)))

        #expect(tab.exchangeState == .empty(.noData))
    }

    @Test func `no contact email leaves the profile alone and says Settings needs it`() async throws {
        let tab = try await tab("VTI", .failure(.missingContactEmail))

        #expect(tab.exchangeMessage == "Add your SEC contact email in Settings to see the exchange.")
    }

    @Test func `another failure says so`() async throws {
        let tab = try await tab("VTI", .failure(.unavailable("Down.")))

        #expect(tab.exchangeMessage != nil)
    }

    /// The directory's download can't be cancelled, and an unknown ticker is
    /// dropped only once its load ends.
    @Test func `an unknown ticker doesn't wait for the directory`() async throws {
        let directory = FakeDirectory()
        let ticker = try Ticker("ZZZZQ")
        let tab = ResearchTabModel(
            ticker: ticker,
            quotes: FakeQuotes(.failure(.unknownTicker(ticker))),
            dailyPrices: FakeDailyPrices(),
            ports: FakeResearchData(directory: directory).ports,
            clock: Date.init,
        )

        await tab.load()

        #expect(directory.lookups.isEmpty)
    }

    @Test func `another quote failure still loads the exchange`() async throws {
        let directory = FakeDirectory()
        let ticker = try Ticker("VTI")
        let tab = ResearchTabModel(
            ticker: ticker,
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: FakeDailyPrices(),
            ports: FakeResearchData(directory: directory).ports,
            clock: Date.init,
        )

        await tab.load()

        #expect(directory.lookups == [ticker])
    }

    @Test func `retrying the exchange after saving the email loads it`() async throws {
        let berkshire = try ListedSecurity(ticker: Ticker("BRK-B"), name: "Berkshire", exchange: "NYSE")
        let quote = try makeQuote(ticker: "BRK-B", price: 12)
        let directory = FakeDirectory(.failure(.missingContactEmail))
        let model = ResearchWindowModel(
            quotes: FakeTickerQuotes(["BRK-B": .success(quote)]),
            dailyPrices: FakeDailyPrices(),
            ports: FakeResearchData(directory: directory).ports,
        )
        await model.open(berkshire.ticker)?.value
        directory.answer(with: .success([berkshire]))

        await model.retry(.exchange, for: berkshire.ticker)?.value

        #expect(model.selectedTab?.exchangeState == .loaded("NYSE"))
        #expect(model.selectedTab?.exchangeMessage == nil)
    }
}
