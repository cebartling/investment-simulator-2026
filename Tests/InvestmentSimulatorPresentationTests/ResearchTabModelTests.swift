import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct ResearchTabModelTests {
    @Test func `starts loading`() throws {
        let tab = try ResearchTabModel(ticker: Ticker("VTI"), quotes: FakeQuotes(.failure(.missingAPIKey)))

        #expect(tab.quoteState == .loading)
        #expect(!tab.needsAPIKey)
    }

    @Test func `refreshing shows the quote`() async throws {
        let quote = try makeQuote(ticker: "VTI", price: 316.9961)
        let tab = try ResearchTabModel(ticker: Ticker("VTI"), quotes: FakeQuotes(.success(quote)))

        await tab.refresh()

        #expect(tab.quoteState == .quoted(quote))
    }

    @Test(arguments: [
        QuoteError.missingAPIKey,
        .invalidAPIKey,
        .dailyLimitReached,
        .unavailable("Equibles is down"),
    ])
    func `refreshing keeps the error`(error: QuoteError) async throws {
        let tab = try ResearchTabModel(ticker: Ticker("VTI"), quotes: FakeQuotes(.failure(error)))

        await tab.refresh()

        #expect(tab.quoteState == .failed(error))
    }

    @Test(arguments: [
        (QuoteError.missingAPIKey, true),
        (.invalidAPIKey, true),
        (.dailyLimitReached, false),
        (.unavailable("Equibles is down"), false),
    ])
    func `only key errors need the API key`(error: QuoteError, needsKey: Bool) async throws {
        let tab = try ResearchTabModel(ticker: Ticker("VTI"), quotes: FakeQuotes(.failure(error)))

        await tab.refresh()

        #expect(tab.needsAPIKey == needsKey)
    }

    @Test func `a later refresh replaces a failure`() async throws {
        let quotes = FakeQuotes(.failure(.missingAPIKey))
        let tab = try ResearchTabModel(ticker: Ticker("VTI"), quotes: quotes)
        await tab.refresh()
        let quote = try makeQuote(ticker: "VTI", price: 12)
        quotes.answer(with: .success(quote))

        await tab.refresh()

        #expect(tab.quoteState == .quoted(quote))
        #expect(!tab.needsAPIKey)
    }

    @Test func `a refresh shows loading while it waits`() async throws {
        let quotes = FakeQuotes(.failure(.missingAPIKey))
        let tab = try ResearchTabModel(ticker: Ticker("VTI"), quotes: quotes)
        await tab.refresh()
        let seen = Seen()
        quotes.whileAnswering { seen.state = tab.quoteState }

        await tab.refresh()

        #expect(seen.state == .loading)
    }

    @Test func `a cancelled refresh leaves the state alone`() async throws {
        let quotes = try FakeTickerQuotes(["VTI": .success(makeQuote(ticker: "VTI", price: 12))])
        let tab = try ResearchTabModel(ticker: Ticker("VTI"), quotes: quotes)
        let run = Run()
        quotes.whileAnsweringNext { run.task?.cancel() }

        run.task = Task { await tab.refresh() }
        await run.task?.value

        #expect(tab.quoteState == .loading)
    }
}

@MainActor
private final class Seen {
    var state: ResearchTabModel.QuoteState?
}

@MainActor
private final class Run {
    var task: Task<Void, Never>?
}
