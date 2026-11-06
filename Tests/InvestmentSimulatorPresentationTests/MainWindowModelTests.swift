import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct MainWindowModelTests {
    @Test func `cash balance comes from the experiment`() async throws {
        let model = try await makeModel(cashBalance: 2500)

        #expect(model.cashBalance == 2500)
    }

    @Test func `window prices holdings with its quotes`() async throws {
        let model = try await makeModelWithPurchase()
        let quotes = try FakeQuotes(.success(makeQuote(price: "12")))
        let priced = try await loadedModel(experiment: model.experiment,
                                           quotes: quotes,
                                           dailyPrices: FakeDailyPrices())

        await priced.holdingsPrices.priceNewHoldings(of: priced.experiment.heldTickers)

        #expect(quotes.requestCount == 1)
        #expect(priced.holdingsPrices.valuation(of: priced.experiment) != .pricing)
    }

    @Test func `purchases come from the experiment`() async throws {
        let purchase = try Purchase(
            id: fixedPurchaseID,
            ticker: Ticker("VTI"),
            shares: 1,
            pricePerShare: 10,
            pricedAt: Date(timeIntervalSince1970: 0),
            priceSource: .liveQuote(delayed: false),
        )
        let model = try await loadedModel(experiment: Experiment(cashBalance: Money(5), purchases: [purchase]),
                                          quotes: FakeQuotes(.failure(.missingAPIKey)),
                                          dailyPrices: FakeDailyPrices())

        #expect(model.purchases == [purchase])
    }

    @Test func `beginning a purchase shows the purchase sheet with the cash balance`() async throws {
        let model = try await makeModel(cashBalance: 500)

        model.beginPurchase()

        #expect(model.isShowingPurchase)
        #expect(model.purchase?.availableCash == Money(500))
    }

    @Test func `completing a purchase updates the experiment and hides the sheet`() async throws {
        let model = try await makeModel(cashBalance: 500, quotes: FakeQuotes(.success(makeQuote(price: "100"))))
        model.beginPurchase()
        let purchase = try #require(model.purchase)
        purchase.tickerText = "VTI"
        purchase.shares = 2
        await purchase.getPrice()

        let updated = try #require(model.completePurchase())

        #expect(updated.cashBalance == Money(300))
        #expect(model.experiment == updated)
        #expect(model.purchases.count == 1)
        #expect(!model.isShowingPurchase)
        #expect(model.purchase == nil)
    }

    @Test func `completing a purchase that can't be bought changes nothing`() async throws {
        let model = try await makeModel(cashBalance: 500)
        model.beginPurchase()

        #expect(model.completePurchase() == nil)
        #expect(model.isShowingPurchase)
        #expect(model.cashBalance == 500)
    }

    @Test func `cancelling a purchase hides the sheet`() async throws {
        let model = try await makeModel(cashBalance: 500)
        model.beginPurchase()

        model.cancelPurchase()

        #expect(!model.isShowingPurchase)
        #expect(model.purchase == nil)
    }

    @Test func `beginning a limit order shows the sheet with the purchase's free shares`() async throws {
        let model = try await makeModelWithPurchase(orders: [makeOrder(shares: 3)])

        try model.beginLimitOrder(of: Ticker("VTI"))

        #expect(model.isShowingLimitOrder)
        #expect(model.limitOrder?.purchase.id == fixedPurchaseID)
        #expect(model.limitOrder?.availableShares == 7)
        #expect(model.limitOrder?.expiresAt == LimitOrder.expiry(forPlacedAt: fixedNow))
    }

    @Test func `completing a limit order places it and hides the sheet`() async throws {
        let model = try await makeModelWithPurchase()
        try model.beginLimitOrder(of: Ticker("VTI"))
        model.limitOrder?.profitPercent = 10
        model.limitOrder?.shares = 4

        let updated = try #require(model.completeLimitOrder())

        #expect(updated.limitOrders.count == 1)
        #expect(updated.limitOrders.first?.shares == 4)
        #expect(updated.limitOrders.first?.placedAt == fixedNow)
        #expect(updated.cashBalance == Money(100))
        #expect(model.experiment == updated)
        #expect(!model.isShowingLimitOrder)
        #expect(model.limitOrder == nil)
    }

    @Test func `completing a limit order that can't be placed changes nothing`() async throws {
        let model = try await makeModelWithPurchase()
        try model.beginLimitOrder(of: Ticker("VTI"))
        model.limitOrder?.profitPercent = -1

        #expect(model.completeLimitOrder() == nil)
        #expect(model.isShowingLimitOrder)
        #expect(model.experiment.limitOrders.isEmpty)
    }

    @Test func `cancelling a limit order hides the sheet`() async throws {
        let model = try await makeModelWithPurchase()
        try model.beginLimitOrder(of: Ticker("VTI"))

        model.cancelLimitOrder()

        #expect(!model.isShowingLimitOrder)
        #expect(model.limitOrder == nil)
    }

    @Test func `limit order rows show the ticker and each order's status`() async throws {
        let expired = try makeOrder(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")),
            shares: 1,
            placedAt: fixedNow.addingTimeInterval(-100 * 86400),
        )
        let filled = try makeOrder(id: #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")), shares: 3)
            .filled(on: "2026-10-28")
        let open = try makeOrder(shares: 2)
        let model = try await makeModelWithPurchase(orders: [expired, filled, open])
        model.showsExpiredAndCancelledOrders = true

        let rows = model.limitOrderRows(at: fixedNow)

        #expect(rows.map(\.id) == [expired.id, filled.id, open.id])
        #expect(rows.map(\.side) == [.sell, .sell, .sell])
        #expect(rows.map(\.ticker.symbol) == ["VTI", "VTI", "VTI"])
        #expect(rows.map(\.status) == [.expired, .filled(sessionDate: "2026-10-28"), .open])
        #expect(
            model.limitOrderRows(at: open.expiresAt).map(\.status)
                == [.expired, .filled(sessionDate: "2026-10-28"), .expired],
        )
    }

    @Test func `limit order is placed at the time Place Order is chosen`() async throws {
        var now = fixedNow
        let model = try await makeModelWithPurchase(clock: { now })
        try model.beginLimitOrder(of: Ticker("VTI"))
        now = fixedNow.addingTimeInterval(3600)

        let updated = try #require(model.completeLimitOrder())

        #expect(updated.limitOrders.first?.placedAt == now)
    }

    func makeModelWithPurchase(
        orders: [LimitOrder] = [],
        clock: @escaping () -> Date = { fixedNow },
        prices: FakeDailyPrices = FakeDailyPrices(),
    ) async throws -> MainWindowModel {
        let purchase = try Purchase(
            id: fixedPurchaseID,
            ticker: Ticker("VTI"),
            shares: 10,
            pricePerShare: 10,
            pricedAt: Date(timeIntervalSince1970: 0),
            priceSource: .liveQuote(delayed: false),
        )
        return try await loadedModel(
            experiment: Experiment(cashBalance: Money(100), purchases: [purchase], limitOrders: orders),
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: prices,
            clock: clock,
        )
    }

    func makeOrder(id: UUID = fixedOrderID, shares: Int, placedAt: Date = fixedNow) throws -> LimitOrder {
        try LimitOrder.placed(id: id, purchaseID: fixedPurchaseID, shares: shares, limitPrice: Money(12), at: placedAt)
    }

    func makeModel(
        cashBalance: Decimal = 0,
        quotes: FakeQuotes = FakeQuotes(.failure(.missingAPIKey)),
        clock: @escaping () -> Date = { fixedNow },
    ) async throws -> MainWindowModel {
        try await loadedModel(experiment: Experiment(cashBalance: Money(cashBalance)),
                              quotes: quotes,
                              dailyPrices: FakeDailyPrices(),
                              clock: clock)
    }
}

/// Check Orders.
extension MainWindowModelTests {
    @Test func `checking orders fills those the bars reach and returns the experiment`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 13)]])
        let model = try await makeModelWithPurchase(
            orders: [makeOrder(shares: 4)],
            clock: { threeDaysLater },
            prices: prices,
        )

        let updated = try #require(await model.checkLimitOrders())

        #expect(updated.limitOrders.map(\.filledOn) == ["2026-10-28"])
        #expect(updated.cashBalance == Money(148))
        #expect(model.experiment == updated)
        #expect(model.orderCheckMessage == "1 order filled.")
        #expect(prices.requests == [.init(ticker: "VTI", startDate: "2026-10-27", endDate: "2026-10-30")])
    }

    @Test func `checking says how many orders filled`() async throws {
        let second = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000A2"))
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 13)]])
        let model = try await makeModelWithPurchase(
            orders: [makeOrder(shares: 4), makeOrder(id: second, shares: 6)],
            clock: { threeDaysLater },
            prices: prices,
        )

        _ = await model.checkLimitOrders()

        #expect(model.orderCheckMessage == "2 orders filled.")
    }

    @Test func `checking with nothing to fill changes nothing`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 11)]])
        let model = try await makeModelWithPurchase(
            orders: [makeOrder(shares: 4)],
            clock: { threeDaysLater },
            prices: prices,
        )
        let before = model.experiment

        #expect(await model.checkLimitOrders() == nil)
        #expect(model.experiment == before)
        #expect(model.orderCheckMessage == "No orders filled.")
    }

    @Test func `a check whose experiment changed while prices loaded fills nothing`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 13)]])
        let model = try await makeModelWithPurchase(
            orders: [makeOrder(shares: 4)],
            clock: { threeDaysLater },
            prices: prices,
        )
        let before = model.experiment
        prices.whileAnswering { model.cancelOrder(id: fixedOrderID) }

        #expect(await model.checkLimitOrders() == nil)
        #expect(model.experiment != before)
        #expect(model.orderCheckMessage == "The experiment changed during the check. Check again.")
    }

    @Test func `a failed check shows the error and changes nothing`() async throws {
        let model = try await makeModelWithPurchase(
            orders: [makeOrder(shares: 4)],
            clock: { threeDaysLater },
            prices: FakeDailyPrices(failure: .dailyLimitReached),
        )
        let before = model.experiment

        #expect(await model.checkLimitOrders() == nil)
        #expect(model.experiment == before)
        #expect(model.orderCheckMessage == QuoteError.dailyLimitReached.localizedDescription)
        #expect(!model.isCheckingOrders)
    }

    @Test func `orders can be checked only when a settled session could fill one`() async throws {
        let order = try makeOrder(shares: 4)

        #expect(try await !makeModelWithPurchase(orders: []).canCheckOrders(at: threeDaysLater))
        #expect(try await makeModelWithPurchase(orders: [order]).canCheckOrders(at: threeDaysLater))
        let filled = try await makeModelWithPurchase(orders: [order.filled(on: "2026-10-28")])
        #expect(!filled.canCheckOrders(at: threeDaysLater))
    }

    @Test func `orders placed today can be checked from tomorrow`() async throws {
        let model = try await makeModelWithPurchase(orders: [makeOrder(shares: 4)])

        #expect(!model.canCheckOrders(at: fixedNow))
        #expect(model.canCheckOrders(at: fixedNow.addingTimeInterval(86400)))
    }
}

/// 7:20 AM in New York on Friday 2026-10-30, three days after `fixedNow`.
let threeDaysLater = fixedNow.addingTimeInterval(3 * 86400)
