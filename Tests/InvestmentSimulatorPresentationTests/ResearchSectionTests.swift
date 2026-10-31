import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct ResearchSectionTests {
    private static let profile = CompanyProfile(
        name: "Apple Inc.",
        sector: "Technology",
        industry: "Consumer Electronics",
        marketCap: Money(5_024_265_535_488),
    )

    private static let multiples: ValuationMultiples = {
        let ratio = ValuationRatio(value: 12, peerMedian: 10, peerP25: 8, peerP75: 14)
        return ValuationMultiples(peRatio: ratio, evToRevenue: ratio, evToEbit: ratio)
    }()

    private static let now = Date(timeIntervalSince1970: 1_793_000_000)

    private static func dividends() throws -> [Dividend] {
        try [Dividend(exDate: "2026-08-10", amountPerShare: 3, currency: "USD")]
    }

    @Test func `sections start loading`() throws {
        let tab = try tab(FakeResearchData())

        #expect(tab.profileState == .loading)
        #expect(tab.multiplesState == .loading)
        #expect(tab.pressReleasesState == .loading)
        #expect(tab.filingsState == .loading)
    }

    @Test func `loading fills in the profile and multiples`() async throws {
        let tab = try tab(FakeResearchData(profile: .success(Self.profile), multiples: .success(Self.multiples)))

        await tab.load()

        #expect(tab.profileState == .loaded(Self.profile))
        #expect(tab.multiplesState == .loaded(Self.multiples))
    }

    @Test func `no data is an empty section, not an error`() async throws {
        let tab = try tab(FakeResearchData())

        await tab.load()

        #expect(tab.profileState == .empty(.noData))
        #expect(tab.multiplesState == .empty(.noData))
    }

    @Test func `a failure stays in its own section`() async throws {
        let tab = try tab(FakeResearchData(
            profile: .success(Self.profile),
            multiples: .failure(.dailyLimitReached),
        ))

        await tab.load()

        #expect(tab.profileState == .loaded(Self.profile))
        #expect(tab.multiplesState == .failed(.dailyLimitReached))
    }

    @Test func `a section failure leaves the quote and chart alone`() async throws {
        let quote = try makeQuote(ticker: "VTI", price: 12)
        let bars = try ["VTI": [makeDailyBar(session: "2026-10-28", high: 2)]]
        let tab = try tab(
            FakeResearchData(profile: .failure(.dailyLimitReached), multiples: .failure(.dailyLimitReached)),
            quotes: FakeTickerQuotes(["VTI": .success(quote)]),
            prices: FakeDailyPrices(bars),
        )

        await tab.load()

        #expect(tab.quoteState == .quoted(quote))
        guard case .loaded = tab.chartState else {
            Issue.record("Expected a chart, got \(tab.chartState)")
            return
        }
    }

    @Test func `loading again shows loading in place of a failure`() async throws {
        let data = FakeResearchData(multiples: .failure(.dailyLimitReached))
        // Its own fake for the other sections, so the check runs during the
        // multiples request and not before that section has started.
        let tab = try tab(data, otherSections: FakeResearchData())
        await tab.load()
        #expect(tab.multiplesState == .failed(.dailyLimitReached))
        data.whileAnswering { #expect(tab.multiplesState == .loading) }

        await tab.load()
    }

    @Test func `a cancelled load leaves the sections alone`() async throws {
        let data = FakeResearchData(profile: .success(Self.profile), multiples: .success(Self.multiples))
        let tab = try tab(data)
        let run = Run()
        data.whileAnswering { run.task?.cancel() }

        run.task = Task { await tab.load() }
        await run.task?.value

        #expect(tab.profileState == .loading)
        #expect(tab.multiplesState == .loading)
        #expect(tab.dividendsState == .loading)
        #expect(tab.pressReleasesState == .loading)
        #expect(tab.filingsState == .loading)
    }

    @Test func `dividends start loading`() throws {
        let tab = try tab(FakeResearchData())

        #expect(tab.dividendsState == .loading)
    }

    @Test func `loading fills in the dividends as of the clock's date`() async throws {
        let tab = try tab(FakeResearchData(dividends: .success(Self.dividends())))

        await tab.load()

        #expect(try tab.dividendsState == .loaded(DividendHistory(dividends: Self.dividends(), asOf: Self.now)))
    }

    @Test func `no dividends is an empty section`() async throws {
        let tab = try tab(FakeResearchData())

        await tab.load()

        #expect(tab.dividendsState == .empty(.noData))
    }

    @Test func `a dividends failure stays in its own section`() async throws {
        let tab = try tab(FakeResearchData(profile: .success(Self.profile), dividends: .failure(.dailyLimitReached)))

        await tab.load()

        #expect(tab.dividendsState == .failed(.dailyLimitReached))
        #expect(tab.profileState == .loaded(Self.profile))
    }

    @Test func `the yield divides the trailing dividends by the quote`() async throws {
        let quote = try makeQuote(ticker: "VTI", price: 12)
        let tab = try tab(FakeResearchData(dividends: .success(Self.dividends())), quotes: FakeQuotes(.success(quote)))

        await tab.load()

        #expect(tab.dividendYield == 0.25)
    }

    @Test func `there's no yield without a quote`() async throws {
        let tab = try tab(FakeResearchData(dividends: .success(Self.dividends())))

        await tab.load()

        #expect(tab.dividendYield == nil)
    }

    @Test func `there's no yield without dividends`() async throws {
        let quote = try makeQuote(ticker: "VTI", price: 12)
        let tab = try tab(FakeResearchData(), quotes: FakeQuotes(.success(quote)))

        await tab.load()

        #expect(tab.dividendYield == nil)
    }

    @Test func `a new quote updates the yield from the dividends already loaded`() async throws {
        let data = try FakeResearchData(dividends: .success(Self.dividends()))
        let quotes = try FakeQuotes(.success(makeQuote(ticker: "VTI", price: 12)))
        let tab = try tab(data, quotes: quotes)
        await tab.load()
        let before = data.requestCount
        try quotes.answer(with: .success(makeQuote(ticker: "VTI", price: 6)))

        await tab.refresh()

        #expect(tab.dividendYield == 0.5)
        #expect(data.requestCount == before)
    }

    @Test func `a load cancelled before it starts asks for nothing`() async throws {
        let data = FakeResearchData(profile: .success(Self.profile), multiples: .success(Self.multiples))
        let quote = try makeQuote(ticker: "VTI", price: 12)
        let quotes = FakeTickerQuotes(["VTI": .success(quote)])
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 2)]])
        let tab = try tab(data, quotes: quotes, prices: prices)
        await tab.load()
        let before = data.requestCount

        let task = Task { await tab.load() }
        task.cancel()
        await task.value

        #expect(data.requestCount == before)
        #expect(quotes.requests == ["VTI"])
        #expect(tab.quoteState == .quoted(quote))
        #expect(tab.profileState == .loaded(Self.profile))
    }

    @Test func `a load cancelled before it starts keeps the charts loaded before`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 2)]])
        let tab = try tab(FakeResearchData(), prices: prices)
        await tab.load()

        let task = Task { await tab.load() }
        task.cancel()
        await task.value
        await tab.showRange(.sixMonths)

        #expect(prices.requests.count == 1)
    }

    @Test(arguments: [
        (ResearchEmptyReason.noData, "No press releases for PLUG."),
        (.nonePublished, "No press releases published for PLUG."),
        (.notCovered, "Equibles doesn't cover PLUG's press releases."),
    ])
    func `each empty reason reads differently`(reason: ResearchEmptyReason, expected: String) throws {
        #expect(try reason.message(subject: "press releases", ticker: Ticker("PLUG")) == expected)
    }

    private func tab(
        _ data: FakeResearchData,
        otherSections: FakeResearchData? = nil,
        quotes: some QuoteProviding = FakeQuotes(.failure(.missingAPIKey)),
        prices: FakeDailyPrices = FakeDailyPrices(),
    ) throws -> ResearchTabModel {
        try ResearchTabModel(
            ticker: Ticker("VTI"),
            quotes: quotes,
            dailyPrices: prices,
            profiles: otherSections ?? data,
            multiples: data,
            dividends: otherSections ?? data,
            pressReleases: otherSections ?? data,
            filings: otherSections ?? data,
            clock: { Self.now },
        )
    }
}

@MainActor
private final class Run {
    var task: Task<Void, Never>?
}
