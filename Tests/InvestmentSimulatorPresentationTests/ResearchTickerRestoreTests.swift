import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct ResearchTickerRestoreTests {
    @Test func `restoring reopens the saved tickers in order and selects the saved one`() async throws {
        let store = FakeTickerStore(symbols: ["VTI", "AAPL", "MSFT"], selected: "AAPL")
        let model = try research(store)

        for task in model.restore() {
            await task.value
        }

        #expect(model.tabs.map(\.ticker.symbol) == ["VTI", "AAPL", "MSFT"])
        #expect(try model.selection == Ticker("AAPL"))
        #expect(try model.selectedTab?.quoteState == .quoted(makeQuote(ticker: "AAPL", price: 20)))
    }

    @Test func `a missing saved selection selects the last ticker`() async throws {
        let store = FakeTickerStore(symbols: ["VTI", "AAPL"], selected: nil)
        let model = try research(store)

        for task in model.restore() {
            await task.value
        }

        #expect(try model.selection == Ticker("AAPL"))
    }

    @Test func `a saved selection that isn't saved among the tickers selects the last ticker`() async throws {
        let store = FakeTickerStore(symbols: ["VTI", "AAPL"], selected: "MSFT")
        let model = try research(store)

        for task in model.restore() {
            await task.value
        }

        #expect(try model.selection == Ticker("AAPL"))
    }

    @Test func `invalid saved symbols are skipped`() async throws {
        let store = FakeTickerStore(symbols: ["VT I", "VTI"], selected: "VTI")
        let model = try research(store)

        for task in model.restore() {
            await task.value
        }

        #expect(model.tabs.map(\.ticker.symbol) == ["VTI"])
        #expect(model.openError == nil)
    }

    @Test func `a saved ticker that is now unknown is dropped and forgotten`() async throws {
        let store = FakeTickerStore(symbols: ["VTI", "ZZZZQ"], selected: "ZZZZQ")
        let model = try research(store)

        for task in model.restore() {
            await task.value
        }

        #expect(model.tabs.map(\.ticker.symbol) == ["VTI"])
        #expect(try model.selection == Ticker("VTI"))
        #expect(store.symbols == ["VTI"])
        #expect(store.selected == "VTI")
    }

    @Test func `restoring leaves an empty store empty`() throws {
        let store = FakeTickerStore(symbols: [], selected: nil)
        let model = try research(store)

        #expect(model.restore().isEmpty)
        #expect(model.tabs.isEmpty)
    }

    @Test func `opening saves the tickers and the selection`() async throws {
        let store = FakeTickerStore(symbols: [], selected: nil)
        let model = try research(store)

        await open("VTI", in: model)
        await open("AAPL", in: model)

        #expect(store.symbols == ["VTI", "AAPL"])
        #expect(store.selected == "AAPL")
    }

    @Test func `selecting saves the selection`() async throws {
        let store = FakeTickerStore(symbols: [], selected: nil)
        let model = try research(store)
        await open("VTI", in: model)
        await open("AAPL", in: model)

        model.selection = try Ticker("VTI")

        #expect(store.selected == "VTI")
    }

    @Test func `closing saves the remaining tickers and the new selection`() async throws {
        let store = FakeTickerStore(symbols: [], selected: nil)
        let model = try research(store)
        await open("VTI", in: model)
        await open("AAPL", in: model)

        try model.close(Ticker("AAPL"))

        #expect(store.symbols == ["VTI"])
        #expect(store.selected == "VTI")
    }

    @Test func `closing the last ticker saves an empty list`() async throws {
        let store = FakeTickerStore(symbols: [], selected: nil)
        let model = try research(store)
        await open("VTI", in: model)

        try model.close(Ticker("VTI"))

        #expect(store.symbols.isEmpty)
        #expect(store.selected == nil)
    }

    @Test func `a ticker dropped as unknown is not saved`() async throws {
        let store = FakeTickerStore(symbols: [], selected: nil)
        let model = try research(store)
        await open("AAPL", in: model)

        await open("ZZZZQ", in: model)

        #expect(store.symbols == ["AAPL"])
        #expect(store.selected == "AAPL")
    }

    private func research(_ store: FakeTickerStore) throws -> ResearchWindowModel {
        let zzzzq = try Ticker("ZZZZQ")
        return try ResearchWindowModel(
            quotes: FakeTickerQuotes([
                "VTI": .success(makeQuote(ticker: "VTI", price: 12)),
                "AAPL": .success(makeQuote(ticker: "AAPL", price: 20)),
                "MSFT": .success(makeQuote(ticker: "MSFT", price: 30)),
                "ZZZZQ": .failure(.unknownTicker(zzzzq)),
            ]),
            dailyPrices: FakeDailyPrices(),
            ports: FakeResearchData().ports,
            tickerStore: store,
            clock: { Self.now },
        )
    }

    /// 2 PM in New York on 2026-10-29.
    private static let now = ISO8601DateFormatter().date(from: "2026-10-29T18:00:00Z")!

    private func open(_ symbol: String, in model: ResearchWindowModel) async {
        model.symbolText = symbol
        await model.open()?.value
    }
}

/// Keeps the saved tickers in memory, as a test must not touch disk (ADR-0007).
@MainActor
private final class FakeTickerStore: ResearchTickerStoring {
    var symbols: [String]
    var selected: String?

    init(symbols: [String], selected: String?) {
        self.symbols = symbols
        self.selected = selected
    }

    func load() -> SavedResearchTickers {
        SavedResearchTickers(symbols: symbols, selected: selected)
    }

    func save(_ tickers: SavedResearchTickers) {
        symbols = tickers.symbols
        selected = tickers.selected
    }
}
