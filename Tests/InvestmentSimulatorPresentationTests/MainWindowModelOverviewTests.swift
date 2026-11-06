import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// A stock card's Overview: its quote, the change since the previous close
/// and the held shares' gain, above the last session (PIN-511).
extension MainWindowModelTests {
    @Test func `a held stock's Overview shows the holdings' quote, its change and the shares' gain`() async throws {
        let quote = try overviewQuote(price: "105")
        let quotes = FakeTickerQuotes(["VTI": .success(quote)])
        let model = try await makeOverviewModel(quotes: quotes)
        await model.holdingsPrices.priceNewHoldings(of: model.experiment.heldTickers)
        try await model.loadLatestSession(of: Ticker("VTI"))

        let overview = try model.overview(of: Ticker("VTI"))

        #expect(overview.price == .quoted(quote))
        // From the Oct 26 close of 100.
        #expect(overview.change?.amount == 5)
        #expect(overview.change?.percent == 5)
        // 10 shares bought at 80 for 800, now worth 1050.
        let gain = try model.experiment.unrealizedGain(of: Ticker("VTI"), at: 105)
        #expect(overview.holding == .priced(marketValue: Money(1050), gain: gain))
        #expect(gain.amount == Money(250))
        #expect(quotes.requests == ["VTI"])
    }

    @Test func `a held stock's Overview waits for its first quote`() async throws {
        let model = try await makeOverviewModel(quotes: FakeTickerQuotes([:]))
        try await model.loadLatestSession(of: Ticker("VTI"))

        let overview = try model.overview(of: Ticker("VTI"))

        #expect(overview.price == .loading)
        #expect(overview.change == nil)
        #expect(overview.holding == .unpriced)
    }

    @Test func `a failed first quote shows its error, and the last session still shows`() async throws {
        let model = try await makeOverviewModel(quotes: FakeTickerQuotes(["VTI": .failure(.dailyLimitReached)]))
        await model.holdingsPrices.priceNewHoldings(of: model.experiment.heldTickers)
        try await model.loadLatestSession(of: Ticker("VTI"))

        let overview = try model.overview(of: Ticker("VTI"))

        #expect(overview.price == .failed(.dailyLimitReached))
        #expect(overview.holding == .unpriced)
        #expect(try overview.lastSession == model.latestSessions[Ticker("VTI")])
        guard case .loaded = overview.lastSession else {
            Issue.record("The last session didn't load")
            return
        }
    }

    @Test func `a failed refresh keeps the Overview's last good quote, with no error`() async throws {
        let quote = try overviewQuote(price: "105")
        let quotes = FakeTickerQuotes(["VTI": .success(quote)])
        let model = try await makeOverviewModel(quotes: quotes)
        await model.holdingsPrices.priceNewHoldings(of: model.experiment.heldTickers)
        quotes.answer("VTI", with: .failure(.unavailable("offline")))

        await model.holdingsPrices.refreshPrices(holding: model.experiment.heldTickers)

        #expect(try model.overview(of: Ticker("VTI")).price == .quoted(quote))
    }

    @Test func `the change waits for the month's sessions, and shows none if they fail`() async throws {
        let quotes = try FakeTickerQuotes(["VTI": .success(overviewQuote(price: "105"))])
        let unloaded = try await makeOverviewModel(quotes: quotes)
        let failed = try await makeOverviewModel(quotes: quotes, prices: FakeDailyPrices(failure: .dailyLimitReached))
        for model in [unloaded, failed] {
            await model.holdingsPrices.priceNewHoldings(of: model.experiment.heldTickers)
        }
        try await failed.loadLatestSession(of: Ticker("VTI"))

        #expect(try unloaded.overview(of: Ticker("VTI")).change == nil)
        #expect(try failed.overview(of: Ticker("VTI")).change == nil)
        #expect(try failed.overview(of: Ticker("VTI")).price == .quoted(overviewQuote(price: "105")))
    }

    @Test func `there is no change without a session before the quote's`() async throws {
        let quotes = try FakeTickerQuotes(["VTI": .success(overviewQuote(price: "105"))])
        let prices = try FakeDailyPrices(["VTI": [bar("2026-10-27", close: "100")]])
        let model = try await makeOverviewModel(quotes: quotes, prices: prices)
        await model.holdingsPrices.priceNewHoldings(of: model.experiment.heldTickers)
        try await model.loadLatestSession(of: Ticker("VTI"))

        #expect(try model.overview(of: Ticker("VTI")).change == nil)
    }

    @Test func `a card with no shares shows its quote on demand, with no market value or gain`() async throws {
        let quote = try overviewQuote(price: "105")
        let quotes = FakeTickerQuotes(["VTI": .success(quote)])
        let sale = try Sale(
            id: UUID(),
            purchaseID: Self.overviewPurchaseID,
            shares: 10,
            pricePerShare: 90,
            soldAt: fixedNow,
            priceSource: .liveQuote(delayed: false),
        )
        let model = try await makeOverviewModel(quotes: quotes, sales: [sale])
        await model.holdingsPrices.priceNewHoldings(of: model.experiment.heldTickers)

        try await model.holdingsPrices.priceOnDemand(Ticker("VTI"))

        let overview = try model.overview(of: Ticker("VTI"))
        #expect(overview.price == .quoted(quote))
        #expect(overview.holding == .notHeld)
        #expect(quotes.requests == ["VTI"])
    }

    private static let overviewPurchaseID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!

    /// 10 VTI bought at 80, with sessions closing at 90 on Oct 23 and 100 on
    /// Oct 26, the session before `fixedNow`'s.
    private func makeOverviewModel(
        quotes: FakeTickerQuotes,
        prices: FakeDailyPrices? = nil,
        sales: [Sale] = [],
    ) async throws -> MainWindowModel {
        let purchase = try Purchase(
            id: Self.overviewPurchaseID,
            ticker: Ticker("VTI"),
            shares: 10,
            pricePerShare: 80,
            pricedAt: Date(timeIntervalSince1970: 0),
            priceSource: .liveQuote(delayed: false),
        )
        let sessions = try FakeDailyPrices(["VTI": [bar("2026-10-23", close: "90"), bar("2026-10-26", close: "100")]])
        return try await loadedModel(
            experiment: Experiment(cashBalance: Money(10000), purchases: [purchase], sales: sales),
            quotes: quotes,
            dailyPrices: prices ?? sessions,
            clock: { fixedNow },
        )
    }

    /// A delayed quote of VTI at `fixedNow`, in the Oct 27 session.
    private func overviewQuote(price: String) throws -> Quote {
        try Quote(
            ticker: Ticker("VTI"),
            price: #require(Decimal(string: price)),
            asOf: fixedNow,
            source: .liveQuote(delayed: true),
        )
    }

    private func bar(_ session: String, close: String) throws -> DailyBar {
        let price = try #require(Decimal(string: close))
        return try DailyBar(sessionDate: session, open: price, high: price, low: price, close: price)
    }
}
