import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct ResearchWindowModelTests {
    @Test func `starts with no tickers`() {
        let model = ResearchWindowModel(quotes: FakeTickerQuotes([:]))

        #expect(model.tabs.isEmpty)
        #expect(model.selection == nil)
        #expect(model.selectedTab == nil)
        #expect(!model.canOpen)
        #expect(model.open() == nil)
    }

    @Test func `an invalid symbol explains itself and can't be opened`() {
        let model = ResearchWindowModel(quotes: FakeTickerQuotes([:]))

        model.symbolText = "VT I"

        #expect(model.symbolMessage == "Enter a ticker symbol, such as VTI.")
        #expect(!model.canOpen)
        #expect(model.open() == nil)
        #expect(model.tabs.isEmpty)
    }

    @Test func `opening adds the ticker, selects it and quotes it`() async throws {
        let quote = try makeQuote(ticker: "VTI", price: 12)
        let model = ResearchWindowModel(quotes: FakeTickerQuotes(["VTI": .success(quote)]))
        model.symbolText = "vti"

        let opening = model.open()

        #expect(model.symbolText.isEmpty)
        #expect(model.tabs.map(\.ticker.symbol) == ["VTI"])
        #expect(try model.selection == Ticker("VTI"))
        await opening?.value
        #expect(model.selectedTab?.quoteState == .quoted(quote))
    }

    @Test func `tickers stay in the order they were opened`() async throws {
        let model = try ResearchWindowModel(quotes: FakeTickerQuotes([
            "VTI": .success(makeQuote(ticker: "VTI", price: 12)),
            "AAPL": .success(makeQuote(ticker: "AAPL", price: 20)),
            "MSFT": .success(makeQuote(ticker: "MSFT", price: 30)),
        ]))

        for symbol in ["VTI", "AAPL", "MSFT"] {
            await open(symbol, in: model)
        }

        #expect(model.tabs.map(\.ticker.symbol) == ["VTI", "AAPL", "MSFT"])
        #expect(try model.selection == Ticker("MSFT"))
    }

    @Test func `opening an open ticker selects it without quoting again`() async throws {
        let quotes = try FakeTickerQuotes([
            "VTI": .success(makeQuote(ticker: "VTI", price: 12)),
            "AAPL": .success(makeQuote(ticker: "AAPL", price: 20)),
        ])
        let model = ResearchWindowModel(quotes: quotes)
        await open("VTI", in: model)
        await open("AAPL", in: model)

        model.symbolText = "vti"
        let opening = model.open()

        #expect(opening == nil)
        #expect(model.symbolText.isEmpty)
        #expect(model.tabs.map(\.ticker.symbol) == ["VTI", "AAPL"])
        #expect(try model.selection == Ticker("VTI"))
        #expect(quotes.requests == ["VTI", "AAPL"])
    }

    @Test func `an unknown ticker is dropped and says why`() async throws {
        let zzzzq = try Ticker("ZZZZQ")
        let model = try ResearchWindowModel(quotes: FakeTickerQuotes([
            "AAPL": .success(makeQuote(ticker: "AAPL", price: 20)),
            "ZZZZQ": .failure(.unknownTicker(zzzzq)),
        ]))
        await open("AAPL", in: model)

        await open("ZZZZQ", in: model)

        #expect(model.tabs.map(\.ticker.symbol) == ["AAPL"])
        #expect(model.openError == .unknownTicker(zzzzq))
        #expect(try model.selection == Ticker("AAPL"))
    }

    @Test func `typing clears the open error`() async throws {
        let zzzzq = try Ticker("ZZZZQ")
        let model = ResearchWindowModel(quotes: FakeTickerQuotes(["ZZZZQ": .failure(.unknownTicker(zzzzq))]))
        await open("ZZZZQ", in: model)

        model.symbolText = "V"

        #expect(model.openError == nil)
    }

    @Test(arguments: [
        QuoteError.missingAPIKey,
        .invalidAPIKey,
        .dailyLimitReached,
        .unavailable("Equibles is down"),
    ])
    func `any other quote error keeps the ticker open`(error: QuoteError) async {
        let model = ResearchWindowModel(quotes: FakeTickerQuotes(["VTI": .failure(error)]))

        await open("VTI", in: model)

        #expect(model.tabs.map(\.ticker.symbol) == ["VTI"])
        #expect(model.selectedTab?.quoteState == .failed(error))
        #expect(model.openError == nil)
    }

    @Test func `refresh quotes the ticker again`() async throws {
        let quotes = FakeTickerQuotes(["VTI": .failure(.missingAPIKey)])
        let model = ResearchWindowModel(quotes: quotes)
        let vti = try Ticker("VTI")
        await open("VTI", in: model)
        let quote = try makeQuote(ticker: "VTI", price: 12)
        quotes.answer("VTI", with: .success(quote))

        await model.refresh(vti)?.value

        #expect(model.selectedTab?.quoteState == .quoted(quote))
    }

    @Test func `closing selects the next ticker, or the previous at the end`() async throws {
        let model = try ResearchWindowModel(quotes: FakeTickerQuotes([
            "VTI": .success(makeQuote(ticker: "VTI", price: 12)),
            "AAPL": .success(makeQuote(ticker: "AAPL", price: 20)),
            "MSFT": .success(makeQuote(ticker: "MSFT", price: 30)),
        ]))
        for symbol in ["VTI", "AAPL", "MSFT"] {
            await open(symbol, in: model)
        }
        model.selection = try Ticker("AAPL")

        try model.close(Ticker("AAPL"))
        #expect(try model.selection == Ticker("MSFT"))

        try model.close(Ticker("MSFT"))
        #expect(try model.selection == Ticker("VTI"))

        try model.close(Ticker("VTI"))
        #expect(model.selection == nil)
        #expect(model.tabs.isEmpty)
    }

    @Test func `closing another ticker keeps the selection`() async throws {
        let model = try ResearchWindowModel(quotes: FakeTickerQuotes([
            "VTI": .success(makeQuote(ticker: "VTI", price: 12)),
            "AAPL": .success(makeQuote(ticker: "AAPL", price: 20)),
        ]))
        await open("VTI", in: model)
        await open("AAPL", in: model)

        try model.close(Ticker("VTI"))

        #expect(try model.selection == Ticker("AAPL"))
        #expect(model.tabs.map(\.ticker.symbol) == ["AAPL"])
    }

    @Test func `closing a ticker mid-quote cancels its quote`() async throws {
        let vti = try Ticker("VTI")
        let quotes = try FakeTickerQuotes(["VTI": .success(makeQuote(ticker: "VTI", price: 12))])
        let model = ResearchWindowModel(quotes: quotes)
        let closed = Closed()
        quotes.whileAnsweringNext {
            closed.tab = model.selectedTab
            model.close(vti)
        }

        await open("VTI", in: model)

        #expect(model.tabs.isEmpty)
        #expect(model.openError == nil)
        #expect(closed.tab?.quoteState == .loading)
    }

    private func open(_ symbol: String, in model: ResearchWindowModel) async {
        model.symbolText = symbol
        await model.open()?.value
    }
}

@MainActor
private final class Closed {
    var tab: ResearchTabModel?
}
