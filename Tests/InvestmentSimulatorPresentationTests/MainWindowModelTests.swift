import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct MainWindowModelTests {
    @Test func `sections are experiment, simulation, results in order`() throws {
        let model = try makeModel()

        #expect(model.sections == [.experiment, .simulation, .results])
    }

    @Test func `initial selection is the first section`() throws {
        let model = try makeModel()

        #expect(model.selection == .experiment)
    }

    @Test(arguments: [
        (NavigationSection.experiment, "Experiment"),
        (.simulation, "Simulation"),
        (.results, "Results"),
    ])
    func `section title`(section: NavigationSection, title: String) {
        #expect(section.title == title)
    }

    @Test func `cash balance comes from the experiment`() throws {
        let model = try makeModel(cashBalance: 2500)

        #expect(model.cashBalance == 2500)
    }

    @Test func `new document shows the new experiment sheet`() throws {
        let model = try makeModel(needsSetup: true)

        #expect(model.isShowingNewExperiment)
    }

    @Test func `opened document does not show the new experiment sheet`() throws {
        let model = try makeModel(needsSetup: false)

        #expect(!model.isShowingNewExperiment)
    }

    @Test func `creating the experiment sets its cash balance and hides the sheet`() throws {
        let model = try makeModel(needsSetup: true)
        model.newExperiment.cashBalance = 10000

        let created = model.createExperiment()

        #expect(try created == Experiment(cashBalance: Money(10000)))
        #expect(model.experiment == created)
        #expect(model.cashBalance == 10000)
        #expect(!model.isShowingNewExperiment)
    }

    @Test func `creating a zero balance experiment still returns it`() throws {
        let model = try makeModel(needsSetup: true)

        #expect(model.createExperiment() == Experiment.empty)
    }

    @Test func `invalid create keeps the sheet and the experiment`() throws {
        let model = try makeModel(cashBalance: 0, needsSetup: true)
        model.newExperiment.cashBalance = -1

        #expect(model.createExperiment() == nil)
        #expect(model.isShowingNewExperiment)
        #expect(model.cashBalance == 0)
    }

    @Test func `replacing the experiment shows the document's new balance`() throws {
        let model = try makeModel(cashBalance: 100)

        try model.replaceExperiment(with: Experiment(cashBalance: Money(250)))

        #expect(model.cashBalance == 250)
    }

    @Test func `window stays open by default`() throws {
        let model = try makeModel(needsSetup: true)

        #expect(!model.shouldCloseWindow)
    }

    @Test func `cancelling the new experiment hides the sheet and closes the window`() throws {
        let model = try makeModel(needsSetup: true)

        model.cancelNewExperiment()

        #expect(!model.isShowingNewExperiment)
        #expect(model.shouldCloseWindow)
    }

    @Test func `purchases come from the experiment`() throws {
        let purchase = try Purchase(
            id: fixedPurchaseID,
            ticker: Ticker("VTI"),
            shares: 1,
            pricePerShare: 10,
            pricedAt: Date(timeIntervalSince1970: 0),
            priceSource: .liveQuote(delayed: false),
        )
        let model = try MainWindowModel(
            experiment: Experiment(cashBalance: Money(5), purchases: [purchase]),
            needsSetup: false,
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: FakeDailyPrices(),
        )

        #expect(model.purchases == [purchase])
    }

    @Test func `beginning a purchase shows the purchase sheet with the cash balance`() throws {
        let model = try makeModel(cashBalance: 500)

        model.beginPurchase()

        #expect(model.isShowingPurchase)
        #expect(model.purchase?.availableCash == Money(500))
    }

    @Test func `completing a purchase updates the experiment and hides the sheet`() async throws {
        let model = try makeModel(cashBalance: 500, quotes: FakeQuotes(.success(makeQuote(price: "100"))))
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

    @Test func `completing a purchase that can't be bought changes nothing`() throws {
        let model = try makeModel(cashBalance: 500)
        model.beginPurchase()

        #expect(model.completePurchase() == nil)
        #expect(model.isShowingPurchase)
        #expect(model.cashBalance == 500)
    }

    @Test func `cancelling a purchase hides the sheet`() throws {
        let model = try makeModel(cashBalance: 500)
        model.beginPurchase()

        model.cancelPurchase()

        #expect(!model.isShowingPurchase)
        #expect(model.purchase == nil)
    }

    @Test func `beginning a limit order shows the sheet with the purchase's free shares`() throws {
        let model = try makeModelWithPurchase(orders: [makeOrder(shares: 3)])

        try model.beginLimitOrder(for: #require(model.purchases.first))

        #expect(model.isShowingLimitOrder)
        #expect(model.limitOrder?.purchase.id == fixedPurchaseID)
        #expect(model.limitOrder?.availableShares == 7)
        #expect(model.limitOrder?.expiresAt == LimitOrder.expiry(forPlacedAt: fixedNow))
    }

    @Test func `completing a limit order places it and hides the sheet`() throws {
        let model = try makeModelWithPurchase()
        try model.beginLimitOrder(for: #require(model.purchases.first))
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

    @Test func `completing a limit order that can't be placed changes nothing`() throws {
        let model = try makeModelWithPurchase()
        try model.beginLimitOrder(for: #require(model.purchases.first))
        model.limitOrder?.profitPercent = -1

        #expect(model.completeLimitOrder() == nil)
        #expect(model.isShowingLimitOrder)
        #expect(model.experiment.limitOrders.isEmpty)
    }

    @Test func `cancelling a limit order hides the sheet`() throws {
        let model = try makeModelWithPurchase()
        try model.beginLimitOrder(for: #require(model.purchases.first))

        model.cancelLimitOrder()

        #expect(!model.isShowingLimitOrder)
        #expect(model.limitOrder == nil)
    }

    @Test func `limit order rows show the ticker and each order's status`() throws {
        let expired = try makeOrder(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")),
            shares: 1,
            placedAt: fixedNow.addingTimeInterval(-100 * 86400),
        )
        let filled = try makeOrder(id: #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")), shares: 3)
            .filled(on: "2026-10-28")
        let open = try makeOrder(shares: 2)
        let model = try makeModelWithPurchase(orders: [expired, filled, open])
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

    @Test func `limit order is placed at the time Place Order is chosen`() throws {
        var now = fixedNow
        let model = try makeModelWithPurchase(clock: { now })
        try model.beginLimitOrder(for: #require(model.purchases.first))
        now = fixedNow.addingTimeInterval(3600)

        let updated = try #require(model.completeLimitOrder())

        #expect(updated.limitOrders.first?.placedAt == now)
    }

    func makeModelWithPurchase(
        orders: [LimitOrder] = [],
        clock: @escaping () -> Date = { fixedNow },
        prices: FakeDailyPrices = FakeDailyPrices(),
    ) throws -> MainWindowModel {
        let purchase = try Purchase(
            id: fixedPurchaseID,
            ticker: Ticker("VTI"),
            shares: 10,
            pricePerShare: 10,
            pricedAt: Date(timeIntervalSince1970: 0),
            priceSource: .liveQuote(delayed: false),
        )
        return try MainWindowModel(
            experiment: Experiment(cashBalance: Money(100), purchases: [purchase], limitOrders: orders),
            needsSetup: false,
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
        needsSetup: Bool = false,
        quotes: FakeQuotes = FakeQuotes(.failure(.missingAPIKey)),
    ) throws -> MainWindowModel {
        try MainWindowModel(
            experiment: Experiment(cashBalance: Money(cashBalance)),
            needsSetup: needsSetup,
            quotes: quotes,
            dailyPrices: FakeDailyPrices(),
        )
    }
}

/// Check Orders.
extension MainWindowModelTests {
    @Test func `checking orders fills those the bars reach and returns the experiment`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 13)]])
        let model = try makeModelWithPurchase(orders: [makeOrder(shares: 4)], clock: { threeDaysLater }, prices: prices)

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
        let model = try makeModelWithPurchase(
            orders: [makeOrder(shares: 4), makeOrder(id: second, shares: 6)],
            clock: { threeDaysLater },
            prices: prices,
        )

        _ = await model.checkLimitOrders()

        #expect(model.orderCheckMessage == "2 orders filled.")
    }

    @Test func `checking with nothing to fill changes nothing`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 11)]])
        let model = try makeModelWithPurchase(orders: [makeOrder(shares: 4)], clock: { threeDaysLater }, prices: prices)
        let before = model.experiment

        #expect(await model.checkLimitOrders() == nil)
        #expect(model.experiment == before)
        #expect(model.orderCheckMessage == "No orders filled.")
    }

    @Test func `a check whose experiment changed while prices loaded changes nothing`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 13)]])
        let model = try makeModelWithPurchase(orders: [makeOrder(shares: 4)], clock: { threeDaysLater }, prices: prices)
        let reverted = try Experiment(cashBalance: Money(100), purchases: model.purchases)
        prices.whileAnswering { model.replaceExperiment(with: reverted) }

        #expect(await model.checkLimitOrders() == nil)
        #expect(model.experiment == reverted)
        #expect(model.orderCheckMessage == "The experiment changed during the check. Check again.")
    }

    @Test func `a failed check shows the error and changes nothing`() async throws {
        let model = try makeModelWithPurchase(
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

    @Test func `orders can be checked only when a settled session could fill one`() throws {
        let order = try makeOrder(shares: 4)

        #expect(try !makeModelWithPurchase(orders: []).canCheckOrders(at: threeDaysLater))
        #expect(try makeModelWithPurchase(orders: [order]).canCheckOrders(at: threeDaysLater))
        #expect(try !makeModelWithPurchase(orders: [order.filled(on: "2026-10-28")]).canCheckOrders(at: threeDaysLater))
    }

    @Test func `orders placed today can be checked from tomorrow`() throws {
        let model = try makeModelWithPurchase(orders: [makeOrder(shares: 4)])

        #expect(!model.canCheckOrders(at: fixedNow))
        #expect(model.canCheckOrders(at: fixedNow.addingTimeInterval(86400)))
    }
}

/// 7:20 AM in New York on Friday 2026-10-30, three days after `fixedNow`.
let threeDaysLater = fixedNow.addingTimeInterval(3 * 86400)
