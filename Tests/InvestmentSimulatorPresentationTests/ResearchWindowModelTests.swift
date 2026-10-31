import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct ResearchWindowModelTests {
    @Test func `starts with no tickers`() {
        let model = research(FakeTickerQuotes([:]))

        #expect(model.tabs.isEmpty)
        #expect(model.selection == nil)
        #expect(model.selectedTab == nil)
        #expect(model.open() == nil)
    }

    @Test func `an invalid symbol explains itself and can't be opened`() {
        let model = research(FakeTickerQuotes([:]))

        model.symbolText = "VT I"

        #expect(model.symbolMessage == "Enter a ticker symbol, such as VTI.")
        #expect(model.open() == nil)
        #expect(model.tabs.isEmpty)
    }

    @Test func `opening adds the ticker, selects it and quotes it`() async throws {
        let quote = try makeQuote(ticker: "VTI", price: 12)
        let model = research(FakeTickerQuotes(["VTI": .success(quote)]))
        model.symbolText = "vti"

        let opening = model.open()

        #expect(model.symbolText.isEmpty)
        #expect(model.tabs.map(\.ticker.symbol) == ["VTI"])
        #expect(try model.selection == Ticker("VTI"))
        await opening?.value
        #expect(model.selectedTab?.quoteState == .quoted(quote))
    }

    @Test func `tickers stay in the order they were opened`() async throws {
        let model = try research(FakeTickerQuotes([
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
        let model = research(quotes)
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
        let model = try research(FakeTickerQuotes([
            "AAPL": .success(makeQuote(ticker: "AAPL", price: 20)),
            "ZZZZQ": .failure(.unknownTicker(zzzzq)),
        ]))
        await open("AAPL", in: model)

        await open("ZZZZQ", in: model)

        #expect(model.tabs.map(\.ticker.symbol) == ["AAPL"])
        #expect(model.openError == .unknownTicker(zzzzq))
        #expect(try model.selection == Ticker("AAPL"))
    }

    @Test(.timeLimit(.minutes(1)))
    func `an unknown ticker is dropped without waiting for its sections`() async throws {
        let zzzzq = try Ticker("ZZZZQ")
        let model = ResearchWindowModel(
            quotes: FakeTickerQuotes(["ZZZZQ": .failure(.unknownTicker(zzzzq))]),
            dailyPrices: UntilCancelled(),
            ports: ResearchSectionPorts(
                profiles: UntilCancelled(),
                multiples: UntilCancelled(),
                dividends: UntilCancelled(),
                pressReleases: UntilCancelled(),
                filings: UntilCancelled(),
            ),
            clock: { Self.now },
        )

        await open("ZZZZQ", in: model)

        #expect(model.tabs.isEmpty)
        #expect(model.openError == .unknownTicker(zzzzq))
    }

    @Test func `an opened ticker loads its sections`() async throws {
        let profile = CompanyProfile(name: "Vanguard", sector: nil, industry: nil, marketCap: nil)
        let model = try ResearchWindowModel(
            quotes: FakeTickerQuotes(["VTI": .success(makeQuote(ticker: "VTI", price: 12))]),
            dailyPrices: FakeDailyPrices(),
            ports: FakeResearchData(profile: .success(profile), multiples: .failure(.dailyLimitReached)).ports,
            clock: { Self.now },
        )

        await open("VTI", in: model)

        #expect(model.selectedTab?.profileState == .loaded(profile))
        #expect(model.selectedTab?.multiplesState == .failed(.dailyLimitReached))
    }

    @Test func `typing clears the open error`() async throws {
        let zzzzq = try Ticker("ZZZZQ")
        let model = research(FakeTickerQuotes(["ZZZZQ": .failure(.unknownTicker(zzzzq))]))
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
        let model = research(FakeTickerQuotes(["VTI": .failure(error)]))

        await open("VTI", in: model)

        #expect(model.tabs.map(\.ticker.symbol) == ["VTI"])
        #expect(model.selectedTab?.quoteState == .failed(error))
        #expect(model.openError == nil)
    }

    @Test func `refresh quotes the ticker again`() async throws {
        let quotes = FakeTickerQuotes(["VTI": .failure(.missingAPIKey)])
        let model = research(quotes)
        let vti = try Ticker("VTI")
        await open("VTI", in: model)
        let quote = try makeQuote(ticker: "VTI", price: 12)
        quotes.answer("VTI", with: .success(quote))

        await model.refresh(vti)?.value

        #expect(model.selectedTab?.quoteState == .quoted(quote))
    }

    @Test func `a refresh that finds the ticker unknown drops it`() async throws {
        let zzzzq = try Ticker("ZZZZQ")
        let quotes = FakeTickerQuotes(["ZZZZQ": .failure(.missingAPIKey)])
        let model = research(quotes)
        await open("ZZZZQ", in: model)
        quotes.answer("ZZZZQ", with: .failure(.unknownTicker(zzzzq)))

        await model.refresh(zzzzq)?.value

        #expect(model.tabs.isEmpty)
        #expect(model.selection == nil)
        #expect(model.openError == .unknownTicker(zzzzq))
    }

    @Test func `closing selects the next ticker, or the previous at the end`() async throws {
        let model = try research(FakeTickerQuotes([
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
        let model = try research(FakeTickerQuotes([
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
        let model = research(quotes)
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

    @Test func `opening charts the ticker too`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 1)]])
        let quotes = try FakeTickerQuotes(["VTI": .success(makeQuote(ticker: "VTI", price: 12))])
        let model = research(quotes, prices: prices)

        await open("VTI", in: model)

        #expect(prices.requests.count == 1)
        guard case .loaded = model.selectedTab?.chartState else {
            Issue.record("Expected a loaded chart, got \(String(describing: model.selectedTab?.chartState))")
            return
        }
    }

    @Test func `showing a range charts it`() async throws {
        let vti = try Ticker("VTI")
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 1)]])
        let quotes = try FakeTickerQuotes(["VTI": .success(makeQuote(ticker: "VTI", price: 12))])
        let model = research(quotes, prices: prices)
        await open("VTI", in: model)

        await model.showRange(.oneYear, for: vti)?.value

        #expect(model.selectedTab?.chartRange == .oneYear)
        #expect(prices.requests.map(\.startDate) == ["2026-04-29", "2025-10-29"])
    }

    @Test func `closing a ticker mid-range cancels the range`() async throws {
        let vti = try Ticker("VTI")
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 1)]])
        let quotes = try FakeTickerQuotes(["VTI": .success(makeQuote(ticker: "VTI", price: 12))])
        let model = research(quotes, prices: prices)
        await open("VTI", in: model)
        let tab = model.selectedTab
        prices.whileAnswering { model.close(vti) }

        await model.showRange(.oneYear, for: vti)?.value

        #expect(model.tabs.isEmpty)
        #expect(tab?.chartState == .loading)
    }

    private func research(
        _ quotes: some QuoteProviding,
        prices: FakeDailyPrices = FakeDailyPrices(),
    ) -> ResearchWindowModel {
        ResearchWindowModel(
            quotes: quotes,
            dailyPrices: prices,
            ports: FakeResearchData().ports,
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

@MainActor
private final class Closed {
    var tab: ResearchTabModel?
}

/// Requests that never answer until their task is cancelled, as on a network
/// that hangs.
private final class UntilCancelled: DailyPriceProviding, CompanyProfileProviding, ValuationMultiplesProviding {
    func dailyBars(
        for _: Ticker,
        from _: String,
        through _: String,
        interval _: BarInterval,
    ) async throws(QuoteError) -> [DailyBar] {
        await hang()
        throw .unavailable("Cancelled")
    }

    func companyProfile(for _: Ticker) async throws(MarketDataError) -> CompanyProfile {
        await hang()
        throw .unavailable("Cancelled")
    }

    func valuationMultiples(for _: Ticker) async throws(MarketDataError) -> ValuationMultiples {
        await hang()
        throw .unavailable("Cancelled")
    }

    fileprivate func hang() async {
        // A stream nothing yields to ends only when its task is cancelled.
        let (stream, continuation) = AsyncStream<Never>.makeStream()
        for await _ in stream {}
        withExtendedLifetime(continuation) {}
    }
}

extension UntilCancelled: DividendProviding {
    func dividends(for _: Ticker) async throws(MarketDataError) -> [Dividend] {
        await hang()
        throw .unavailable("Cancelled")
    }
}

extension UntilCancelled: PressReleaseProviding, FilingProviding {
    func pressReleases(for _: Ticker) async throws(MarketDataError) -> PressReleases {
        await hang()
        throw .unavailable("Cancelled")
    }

    func filings(for _: Ticker) async throws(MarketDataError) -> [Filing] {
        await hang()
        throw .unavailable("Cancelled")
    }
}
