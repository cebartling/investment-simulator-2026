import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// Buy limit orders and cancelling orders (PIN-404).
extension MainWindowModelTests {
    @Test func `beginning a buy limit order shows the sheet with the available cash`() throws {
        let model = try makeModelWithBuyOrders([makeBuyOrder(shares: 4)])

        model.beginBuyLimitOrder()

        #expect(model.isShowingBuyLimitOrder)
        #expect(model.buyLimitOrder?.availableCash == Money(64))
    }

    @Test func `completing a buy limit order places it, reserves its cash and hides the sheet`() throws {
        let model = try makeModelWithBuyOrders()
        model.beginBuyLimitOrder()
        model.buyLimitOrder?.tickerText = "VTI"
        model.buyLimitOrder?.shares = 4
        model.buyLimitOrder?.enteredPrice = 9

        let updated = try #require(model.completeBuyLimitOrder())

        #expect(updated.buyLimitOrders.count == 1)
        #expect(updated.buyLimitOrders.first?.placedAt == fixedNow)
        #expect(updated.cashBalance == Money(100))
        #expect(model.experiment == updated)
        #expect(model.reservedCash(at: fixedNow) == 36)
        #expect(!model.isShowingBuyLimitOrder)
        #expect(model.buyLimitOrder == nil)
    }

    @Test func `completing a buy limit order that can't be placed changes nothing`() throws {
        let model = try makeModelWithBuyOrders()
        model.beginBuyLimitOrder()

        #expect(model.completeBuyLimitOrder() == nil)
        #expect(model.isShowingBuyLimitOrder)
        #expect(model.experiment.buyLimitOrders.isEmpty)
    }

    @Test func `cancelling the buy limit order sheet hides it`() throws {
        let model = try makeModelWithBuyOrders()
        model.beginBuyLimitOrder()

        model.cancelBuyLimitOrder()

        #expect(!model.isShowingBuyLimitOrder)
        #expect(model.buyLimitOrder == nil)
    }

    @Test func `the buy sheet can't spend cash reserved by an open buy order`() throws {
        let model = try makeModelWithBuyOrders([makeBuyOrder(shares: 4)])

        model.beginPurchase()

        #expect(model.purchase?.availableCash == Money(64))
    }

    @Test func `order rows show buy and sell orders in the order they were placed`() throws {
        let sell = try makeOrder(shares: 2, placedAt: fixedNow.addingTimeInterval(60))
        let buy = try makeBuyOrder(shares: 4)
        let model = try makeModelWithBuyOrders([buy], sellOrders: [sell])

        let rows = model.limitOrderRows(at: fixedNow.addingTimeInterval(120))

        #expect(rows.map(\.id) == [buy.id, sell.id])
        #expect(rows.map(\.side) == [.buy, .sell])
        #expect(rows.map(\.ticker.symbol) == ["AAPL", "VTI"])
        #expect(rows.map(\.shares) == [4, 2])
        #expect(rows.map(\.limitPrice) == [Money(9), Money(12)])
        #expect(rows.map(\.status) == [.open, .open])
    }

    @Test func `a filled buy order's row shows its session`() throws {
        let buy = try makeBuyOrder(shares: 4)
        let model = try MainWindowModel(
            experiment: Experiment(cashBalance: Money(100)).placing(buy).fillingBuyOrder(
                orderID: buy.id,
                on: "2026-10-28",
            ),
            needsSetup: false,
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: FakeDailyPrices(),
            clock: { fixedNow },
        )

        #expect(model.limitOrderRows(at: fixedNow).map(\.status) == [.filled(sessionDate: "2026-10-28")])
    }

    @Test func `cancelling an open order frees it and returns the experiment`() throws {
        var now = fixedNow
        let buy = try makeBuyOrder(shares: 4)
        let sell = try makeOrder(shares: 2)
        let model = try makeModelWithBuyOrders([buy], sellOrders: [sell], clock: { now })
        now = fixedNow.addingTimeInterval(3600)

        let afterBuy = try #require(model.cancelOrder(id: buy.id))
        let afterSell = try #require(model.cancelOrder(id: sell.id))

        #expect(afterBuy.buyLimitOrders.first?.cancelledAt == now)
        #expect(afterSell.limitOrders.first?.cancelledAt == now)
        #expect(model.experiment == afterSell)
        #expect(model.reservedCash(at: now) == 0)
        #expect(model.limitOrderRows(at: now).map(\.status) == [.cancelled, .cancelled])
    }

    @Test func `cancelling an order that isn't open changes nothing`() throws {
        let sell = try makeOrder(shares: 2).filled(on: "2026-10-28")
        let model = try makeModelWithBuyOrders(sellOrders: [sell])
        let before = model.experiment

        #expect(model.cancelOrder(id: sell.id) == nil)
        #expect(model.cancelOrder(id: UUID()) == nil)
        #expect(model.experiment == before)
    }

    @Test func `checking orders fills buy orders and counts them`() async throws {
        let bar = try DailyBar(sessionDate: "2026-10-28", open: 10, high: 10, low: 8, close: 9)
        let prices = FakeDailyPrices(["AAPL": [bar]])
        let model = try makeModelWithBuyOrders([makeBuyOrder(shares: 4)], clock: { threeDaysLater }, prices: prices)

        let updated = try #require(await model.checkLimitOrders())

        #expect(updated.buyLimitOrders.map(\.filledOn) == ["2026-10-28"])
        #expect(updated.cashBalance == Money(64))
        #expect(updated.purchases.map(\.id) == [fixedPurchaseID, fixedBuyOrderID])
        #expect(model.orderCheckMessage == "1 order filled.")
        #expect(model.celebrationCount == 1)
        #expect(prices.requests == [.init(ticker: "AAPL", startDate: "2026-10-27", endDate: "2026-10-30")])
    }

    @Test func `an open buy order can be checked from the next day`() throws {
        let model = try makeModelWithBuyOrders([makeBuyOrder(shares: 4)])

        #expect(!model.canCheckOrders(at: fixedNow))
        #expect(model.canCheckOrders(at: threeDaysLater))
    }

    /// A model with $100 of cash, a VTI purchase of 10 shares, and `buyOrders`
    /// and `sellOrders` placed.
    func makeModelWithBuyOrders(
        _ buyOrders: [BuyLimitOrder] = [],
        sellOrders: [LimitOrder] = [],
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
        var experiment = try Experiment(cashBalance: Money(100), purchases: [purchase], limitOrders: sellOrders)
        for order in buyOrders {
            experiment = try experiment.placing(order)
        }
        return MainWindowModel(
            experiment: experiment,
            needsSetup: false,
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: prices,
            clock: clock,
        )
    }

    /// An AAPL buy order at $9 a share, placed at `fixedNow`.
    func makeBuyOrder(shares: Int) throws -> BuyLimitOrder {
        try BuyLimitOrder.placed(
            id: fixedBuyOrderID,
            ticker: Ticker("AAPL"),
            shares: shares,
            limitPrice: Money(9),
            at: fixedNow,
        )
    }
}

let fixedBuyOrderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
