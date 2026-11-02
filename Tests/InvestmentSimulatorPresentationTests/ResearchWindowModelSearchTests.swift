import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct ResearchWindowModelSearchTests {
    private let apple: ListedSecurity
    private let hospitality: ListedSecurity

    init() throws {
        apple = try ListedSecurity(ticker: Ticker("AAPL"), name: "Apple Inc.", cik: 320_193, exchange: "Nasdaq")
        hospitality = try ListedSecurity(
            ticker: Ticker("APLE"), name: "Apple Hospitality REIT", cik: 1_418_121, exchange: "NYSE",
        )
    }

    private func research(_ directory: FakeDirectory, quotes: FakeTickerQuotes? = nil) -> ResearchWindowModel {
        ResearchWindowModel(
            quotes: quotes ?? FakeTickerQuotes([:]),
            dailyPrices: FakeDailyPrices(),
            ports: FakeResearchData(directory: directory).ports,
            tickerStore: NoResearchTickerStore(),
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

    @Test func `entering a company name opens its top match`() async throws {
        let quote = try makeQuote(ticker: "AAPL", price: 12)
        let model = research(
            FakeDirectory(.success([apple, hospitality])),
            quotes: FakeTickerQuotes(["AAPL": .success(quote)]),
        )
        model.symbolText = "apple"
        await model.search()

        await model.open()?.value

        #expect(model.symbolText.isEmpty)
        #expect(model.selection == apple.ticker)
        #expect(model.selectedTab?.quoteState == .quoted(quote))
    }

    @Test func `entering a name with spaces opens its top match`() async throws {
        let quote = try makeQuote(ticker: "AAPL", price: 12)
        let model = research(
            FakeDirectory(.success([apple])),
            quotes: FakeTickerQuotes(["AAPL": .success(quote)]),
        )
        model.symbolText = "apple inc"
        await model.search()

        await model.open()?.value

        #expect(model.selection == apple.ticker)
        #expect(model.symbolMessage == nil)
    }

    @Test func `a top match that turns out unknown brings the name back`() async throws {
        let quotes = try FakeTickerQuotes(["AAPL": .failure(.unknownTicker(Ticker("AAPL")))])
        let model = research(FakeDirectory(.success([apple])), quotes: quotes)
        model.symbolText = "apple"
        await model.search()

        await model.open()?.value

        #expect(model.symbolText == "apple")
        #expect(model.openError == .unknownTicker(apple.ticker))
    }

    /// The first search can still be downloading the directory.
    @Test func `a company name entered before its search answers comes back with its matches`() async throws {
        let unknown = try Ticker("APPLE")
        let model = research(
            FakeDirectory(.success([apple, hospitality])),
            quotes: FakeTickerQuotes(["APPLE": .failure(.unknownTicker(unknown))]),
        )
        model.symbolText = "apple"

        await model.open()?.value
        await model.search()

        #expect(model.tabs.isEmpty)
        #expect(model.symbolText == "apple")
        #expect(model.openError == .unknownTicker(unknown))
        #expect(model.searchResults == [apple, hospitality])
    }

    @Test func `matches for earlier text are not opened`() async throws {
        let quote = try makeQuote(ticker: "VTI", price: 12)
        let model = research(
            FakeDirectory(.success([apple])),
            quotes: FakeTickerQuotes(["VTI": .success(quote)]),
        )
        model.symbolText = "apple"
        await model.search()

        model.symbolText = "vti"
        await model.open()?.value

        #expect(try model.selection == Ticker("VTI"))
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

    /// Return can come before the first search has its download.
    @Test func `matches for a name rejected as a ticker clear the rejection`() async {
        let model = research(FakeDirectory(.success([apple])))
        model.symbolText = "apple inc"
        model.open()

        await model.search()

        #expect(model.symbolMessage == nil)
        #expect(model.searchResults == [apple])
    }

    @Test func `no matches leave a rejected ticker's message`() async {
        let model = research(FakeDirectory())
        model.symbolText = "apple inc"
        model.open()

        await model.search()

        #expect(model.symbolMessage != nil)
    }

    /// EDGAR spells a share class `BRK-B`, and a typed one is often `BRK.B`.
    @Test func `opening a share class spelled another way selects its open tab`() async throws {
        let dotted = try Ticker("BRK.B")
        let dashed = try Ticker("BRK-B")
        let quote = try makeQuote(ticker: "BRK.B", price: 12)
        let model = research(FakeDirectory(), quotes: FakeTickerQuotes(["BRK.B": .success(quote)]))
        await model.open(dotted)?.value

        await model.open(dashed)?.value

        #expect(model.tabs.map(\.ticker) == [dotted])
        #expect(model.selection == dotted)
    }

    /// A ticker EDGAR lacks could otherwise open a security it merely starts.
    @Test func `entering text that matches a symbol opens what was typed`() async throws {
        let quote = try makeQuote(ticker: "VTI", price: 12)
        let longerSymbol = try ListedSecurity(ticker: Ticker("VTIP"), name: "Other Co", cik: 2, exchange: "Nasdaq")
        let model = research(
            FakeDirectory(.success([longerSymbol])),
            quotes: FakeTickerQuotes(["VTI": .success(quote)]),
        )
        model.symbolText = "vti"
        await model.search()

        await model.open()?.value

        #expect(try model.selection == Ticker("VTI"))
    }
}
