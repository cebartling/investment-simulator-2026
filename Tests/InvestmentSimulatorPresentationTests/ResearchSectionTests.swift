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

    @Test func `sections start loading`() throws {
        let tab = try tab(FakeResearchData())

        #expect(tab.profileState == .loading)
        #expect(tab.multiplesState == .loading)
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

        #expect(tab.profileState == .empty)
        #expect(tab.multiplesState == .empty)
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
        let tab = try tab(data)
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
    }

    @Test func `a load cancelled before it starts asks for nothing`() async throws {
        let data = FakeResearchData(profile: .success(Self.profile), multiples: .success(Self.multiples))
        let tab = try tab(data)
        await tab.load()
        let before = data.requestCount

        let task = Task { await tab.load() }
        task.cancel()
        await task.value

        #expect(data.requestCount == before)
        #expect(tab.profileState == .loaded(Self.profile))
    }

    private func tab(
        _ data: FakeResearchData,
        quotes: some QuoteProviding = FakeQuotes(.failure(.missingAPIKey)),
        prices: FakeDailyPrices = FakeDailyPrices(),
    ) throws -> ResearchTabModel {
        try ResearchTabModel(
            ticker: Ticker("VTI"),
            quotes: quotes,
            dailyPrices: prices,
            profiles: data,
            multiples: data,
            clock: { Date(timeIntervalSince1970: 1_793_000_000) },
        )
    }
}

@MainActor
private final class Run {
    var task: Task<Void, Never>?
}
