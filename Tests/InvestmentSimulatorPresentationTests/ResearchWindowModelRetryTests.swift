import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct ResearchWindowModelRetryTests {
    @Test func `retrying a section leaves the rest of the ticker alone`() async throws {
        let vti = try Ticker("VTI")
        let profile = CompanyProfile(name: "Vanguard", sector: nil, industry: nil, marketCap: nil)
        let ratio = ValuationRatio(value: 12, peerMedian: nil, peerP25: nil, peerP75: nil)
        let multiples = ValuationMultiples(peRatio: ratio, evToRevenue: ratio, evToEbit: ratio)
        let quotes = try FakeTickerQuotes(["VTI": .success(makeQuote(ticker: "VTI", price: 12))])
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 1)]])
        let data = FakeResearchData(profile: .success(profile), multiples: .failure(.unavailable("Down")))
        let model = research(quotes, prices: prices, data: data)
        await open("VTI", in: model)
        let tab = try #require(model.selectedTab)
        let chart = tab.chartState
        data.answerMultiples(with: .success(multiples))

        await model.retry(.multiples, for: vti)?.value

        #expect(tab.multiplesState == .loaded(multiples))
        #expect(tab.profileState == .loaded(profile))
        #expect(tab.chartState == chart)
        #expect(quotes.requests == ["VTI"])
        #expect(prices.requests.count == 1)
        #expect(data.requestCount == 6)
    }

    @Test func `retrying dividends reloads them`() async throws {
        let vti = try Ticker("VTI")
        let dividends = try [Dividend(exDate: "2026-08-10", amountPerShare: 1, currency: "USD")]
        let data = FakeResearchData(dividends: .failure(.unavailable("Down")))
        let model = research(FakeTickerQuotes(["VTI": .failure(.missingAPIKey)]), data: data)
        await open("VTI", in: model)
        let tab = try #require(model.selectedTab)
        data.answerDividends(with: .success(dividends))

        await model.retry(.dividends, for: vti)?.value

        #expect(tab.dividendsState == .loaded(DividendHistory(
            dividends: dividends,
            asOf: Date(timeIntervalSince1970: 1_793_000_000),
        )))
    }

    @Test func `retrying press releases reloads them`() async throws {
        let vti = try Ticker("VTI")
        let data = FakeResearchData(pressReleases: .failure(.unavailable("Down")))
        let model = research(FakeTickerQuotes(["VTI": .failure(.missingAPIKey)]), data: data)
        await open("VTI", in: model)
        let tab = try #require(model.selectedTab)
        data.answerPressReleases(with: .success(PressReleases(coverage: .attempted, releases: [])))

        await model.retry(.pressReleases, for: vti)?.value

        #expect(tab.pressReleasesState == .empty(.notCovered))
    }

    @Test func `retrying filings reloads them`() async throws {
        let vti = try Ticker("VTI")
        let filing = try Filing(
            form: "10-K",
            filedDate: "2026-07-31",
            reportingForDate: nil,
            url: #require(URL(string: "https://example.com/filing")),
        )
        let data = FakeResearchData(filings: .failure(.unavailable("Down")))
        let model = research(FakeTickerQuotes(["VTI": .failure(.missingAPIKey)]), data: data)
        await open("VTI", in: model)
        let tab = try #require(model.selectedTab)
        data.answerFilings(with: .success([filing]))

        await model.retry(.filings, for: vti)?.value

        #expect(tab.filingsState == .loaded([filing]))
    }

    @Test func `retrying a section of a closed ticker does nothing`() throws {
        let model = research(FakeTickerQuotes([:]))

        #expect(try model.retry(.profile, for: Ticker("VTI")) == nil)
    }

    @Test func `closing a ticker mid-retry cancels the retry`() async throws {
        let vti = try Ticker("VTI")
        let data = FakeResearchData(multiples: .failure(.unavailable("Down")))
        let model = research(FakeTickerQuotes(["VTI": .failure(.missingAPIKey)]), data: data)
        await open("VTI", in: model)
        let tab = try #require(model.selectedTab)
        data.whileAnswering { model.close(vti) }

        await model.retry(.multiples, for: vti)?.value

        #expect(model.tabs.isEmpty)
        #expect(tab.multiplesState == .loading)
    }

    @Test func `a refresh cancels a retry still loading`() async throws {
        let vti = try Ticker("VTI")
        let model = research(FakeTickerQuotes(["VTI": .failure(.missingAPIKey)]))
        await open("VTI", in: model)
        let retry = try #require(model.retry(.multiples, for: vti))

        await model.refresh(vti)?.value

        #expect(retry.isCancelled)
    }

    @Test func `dropping an unknown ticker cancels a retry that began after its refresh`() async throws {
        let zzzzq = try Ticker("ZZZZQ")
        let quotes = FakeTickerQuotes(["ZZZZQ": .failure(.missingAPIKey)])
        let model = research(quotes)
        await open("ZZZZQ", in: model)
        quotes.answer("ZZZZQ", with: .failure(.unknownTicker(zzzzq)))
        let refresh = try #require(model.refresh(zzzzq))
        let retry = try #require(model.retry(.multiples, for: zzzzq))

        await refresh.value

        #expect(model.tabs.isEmpty)
        #expect(retry.isCancelled)
    }

    private func research(
        _ quotes: some QuoteProviding,
        prices: FakeDailyPrices = FakeDailyPrices(),
        data: FakeResearchData = FakeResearchData(),
    ) -> ResearchWindowModel {
        ResearchWindowModel(
            quotes: quotes,
            dailyPrices: prices,
            profiles: data,
            multiples: data,
            dividends: data,
            pressReleases: data,
            filings: data,
            clock: { Date(timeIntervalSince1970: 1_793_000_000) },
        )
    }

    private func open(_ symbol: String, in model: ResearchWindowModel) async {
        model.symbolText = symbol
        await model.open()?.value
    }
}
