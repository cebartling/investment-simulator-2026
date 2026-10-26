import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// Celebrations (PIN-403).
extension MainWindowModelTests {
    @Test func `a new window has nothing to celebrate`() throws {
        #expect(try makeModel().celebrationCount == 0)
    }

    @Test func `completing a purchase celebrates`() async throws {
        let model = try makeModel(cashBalance: 500, quotes: FakeQuotes(.success(makeQuote(price: "100"))))
        model.beginPurchase()
        let purchase = try #require(model.purchase)
        purchase.tickerText = "VTI"
        await purchase.getPrice()

        _ = model.completePurchase()

        #expect(model.celebrationCount == 1)
    }

    @Test func `a purchase that can't be bought or is cancelled doesn't celebrate`() throws {
        let model = try makeModel(cashBalance: 500)
        model.beginPurchase()
        _ = model.completePurchase()
        model.cancelPurchase()

        #expect(model.celebrationCount == 0)
    }

    @Test func `placing a limit order doesn't celebrate`() throws {
        let model = try makeModelWithPurchase()
        try model.beginLimitOrder(for: #require(model.purchases.first))
        model.limitOrder?.profitPercent = 10

        _ = try #require(model.completeLimitOrder())

        #expect(model.celebrationCount == 0)
    }

    @Test func `a check that fills several orders celebrates once`() async throws {
        let second = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000A2"))
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 13)]])
        let model = try makeModelWithPurchase(
            orders: [makeOrder(shares: 4), makeOrder(id: second, shares: 6)],
            clock: { threeDaysLater },
            prices: prices,
        )

        _ = try #require(await model.checkLimitOrders())

        #expect(model.celebrationCount == 1)
    }

    @Test func `a check that fills nothing doesn't celebrate`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 11)]])
        let model = try makeModelWithPurchase(orders: [makeOrder(shares: 4)], clock: { threeDaysLater }, prices: prices)

        _ = await model.checkLimitOrders()

        #expect(model.celebrationCount == 0)
    }

    @Test func `a failed check doesn't celebrate`() async throws {
        let model = try makeModelWithPurchase(
            orders: [makeOrder(shares: 4)],
            clock: { threeDaysLater },
            prices: FakeDailyPrices(failure: .dailyLimitReached),
        )

        _ = await model.checkLimitOrders()

        #expect(model.celebrationCount == 0)
    }

    @Test func `a check whose experiment changed doesn't celebrate`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 13)]])
        let model = try makeModelWithPurchase(orders: [makeOrder(shares: 4)], clock: { threeDaysLater }, prices: prices)
        let reverted = try Experiment(cashBalance: Money(100), purchases: model.purchases)
        prices.whileAnswering { model.replaceExperiment(with: reverted) }

        _ = await model.checkLimitOrders()

        #expect(model.celebrationCount == 0)
    }

    @Test func `creating or replacing the experiment doesn't celebrate`() throws {
        let model = try makeModel(needsSetup: true)
        model.newExperiment.cashBalance = 1000
        _ = model.createExperiment()
        try model.replaceExperiment(with: Experiment(cashBalance: Money(250)))

        #expect(model.celebrationCount == 0)
    }
}
