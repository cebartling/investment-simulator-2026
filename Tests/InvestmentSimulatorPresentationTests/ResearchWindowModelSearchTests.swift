import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct ResearchWindowModelSearchTests {
    private let apple: ListedSecurity
    private let hospitality: ListedSecurity

    init() throws {
        apple = try ListedSecurity(ticker: Ticker("AAPL"), name: "Apple Inc.", exchange: "Nasdaq")
        hospitality = try ListedSecurity(ticker: Ticker("APLE"), name: "Apple Hospitality REIT", exchange: "NYSE")
    }

    private func research(_ directory: FakeDirectory, quotes: FakeTickerQuotes? = nil) -> ResearchWindowModel {
        ResearchWindowModel(
            quotes: quotes ?? FakeTickerQuotes([:]),
            dailyPrices: FakeDailyPrices(),
            ports: FakeResearchData(directory: directory).ports,
        )
    }

    @Test func `searching lists the matches`() async {
        let model = research(FakeDirectory(.success([apple, hospitality])))
        model.symbolText = "apple"

        await model.search()

        #expect(model.searchResults == [apple, hospitality])
        #expect(model.searchMessage == nil)
    }

    @Test func `a name with spaces can be searched and raises no ticker message`() async {
        let model = research(FakeDirectory(.success([apple])))
        model.symbolText = "apple inc"

        await model.search()

        #expect(model.searchResults == [apple])
        #expect(model.symbolMessage == nil)
    }

    @Test func `blank text clears the results without searching`() async {
        let directory = FakeDirectory(.success([apple]))
        let model = research(directory)
        model.symbolText = "apple"
        await model.search()

        model.symbolText = "  "
        await model.search()

        #expect(model.searchResults.isEmpty)
        #expect(directory.searches == ["apple"])
    }

    @Test func `no contact email says Settings needs it`() async {
        let model = research(FakeDirectory(.failure(.missingContactEmail)))
        model.symbolText = "apple"

        await model.search()

        #expect(model.searchResults.isEmpty)
        #expect(model.searchMessage == "Add your SEC contact email in Settings to search by company name.")
    }

    @Test func `a failed search says so and drops older results`() async {
        let directory = FakeDirectory(.success([apple]))
        let model = research(directory)
        model.symbolText = "apple"
        await model.search()
        directory.answer(with: .failure(.unavailable("Down.")))

        model.symbolText = "apple i"
        await model.search()

        #expect(model.searchResults.isEmpty)
        #expect(model.searchMessage != nil)
    }

    @Test func `a good search clears an earlier failure`() async {
        let directory = FakeDirectory(.failure(.unavailable("Down.")))
        let model = research(directory)
        model.symbolText = "apple"
        await model.search()
        directory.answer(with: .success([apple]))

        await model.search()

        #expect(model.searchMessage == nil)
    }

    @Test func `results for text since changed are dropped`() async {
        let directory = FakeDirectory(.success([apple]))
        let model = research(directory)
        directory.whileAnswering { model.symbolText = "" }
        model.symbolText = "apple"

        await model.search()

        #expect(model.searchResults.isEmpty)
    }

    @Test func `no contact email still opens a typed ticker`() async throws {
        let quote = try makeQuote(ticker: "VTI", price: 12)
        let model = research(
            FakeDirectory(.failure(.missingContactEmail)),
            quotes: FakeTickerQuotes(["VTI": .success(quote)]),
        )
        model.symbolText = "vti"
        await model.search()

        await model.open()?.value

        #expect(model.selectedTab?.quoteState == .quoted(quote))
    }

    @Test func `opening a result opens its ticker and clears the search`() async throws {
        let quote = try makeQuote(ticker: "AAPL", price: 12)
        let model = research(
            FakeDirectory(.success([apple])),
            quotes: FakeTickerQuotes(["AAPL": .success(quote)]),
        )
        model.symbolText = "apple"
        await model.search()

        await model.open(apple.ticker)?.value

        #expect(model.symbolText.isEmpty)
        #expect(model.searchResults.isEmpty)
        #expect(model.selection == apple.ticker)
        #expect(model.selectedTab?.quoteState == .quoted(quote))
    }

    /// The directory's top match could be another security, so Return
    /// never picks one.
    @Test func `a company name entered as a ticker comes back with its matches`() async throws {
        let unknown = try Ticker("APPLE")
        let model = research(
            FakeDirectory(.success([apple, hospitality])),
            quotes: FakeTickerQuotes(["APPLE": .failure(.unknownTicker(unknown))]),
        )
        model.symbolText = "apple"
        await model.search()

        await model.open()?.value
        await model.search()

        #expect(model.tabs.isEmpty)
        #expect(model.symbolText == "apple")
        #expect(model.openError == .unknownTicker(unknown))
        #expect(model.searchResults == [apple, hospitality])
    }

    @Test func `a company name entered without the email comes back saying Settings needs it`() async throws {
        let unknown = try Ticker("APPLE")
        let model = research(
            FakeDirectory(.failure(.missingContactEmail)),
            quotes: FakeTickerQuotes(["APPLE": .failure(.unknownTicker(unknown))]),
        )
        model.symbolText = "apple"
        await model.search()

        await model.open()?.value
        await model.search()

        #expect(model.openError == .unknownTicker(unknown))
        #expect(model.searchMessage == "Add your SEC contact email in Settings to search by company name.")
    }

    @Test func `text typed while an unknown ticker loads is kept`() async throws {
        let unknown = try Ticker("APPLE")
        let quotes = FakeTickerQuotes(["APPLE": .failure(.unknownTicker(unknown))])
        let model = research(FakeDirectory(), quotes: quotes)
        model.symbolText = "apple"
        let opening = model.open()

        model.symbolText = "msft"
        await opening?.value

        #expect(model.symbolText == "msft")
    }

    @Test func `a chosen match that turns out unknown leaves the field empty`() async throws {
        let quotes = try FakeTickerQuotes(["AAPL": .failure(.unknownTicker(Ticker("AAPL")))])
        let model = research(FakeDirectory(.success([apple])), quotes: quotes)
        model.symbolText = "apple"
        await model.search()

        await model.open(apple.ticker)?.value

        #expect(model.symbolText.isEmpty)
        #expect(model.openError != nil)
    }

    @Test func `entering text opens what was typed, not the top match`() async throws {
        let quote = try makeQuote(ticker: "APP", price: 12)
        let model = research(
            FakeDirectory(.success([apple])),
            quotes: FakeTickerQuotes(["APP": .success(quote)]),
        )
        model.symbolText = "app"
        await model.search()

        await model.open()?.value

        #expect(try model.selection == Ticker("APP"))
    }
}

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
}
