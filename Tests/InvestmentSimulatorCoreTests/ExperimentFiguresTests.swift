import Foundation
import InvestmentSimulatorCore
import Testing

/// The figures the Experiment header reports (PIN-408).
struct ExperimentFiguresTests {
    @Test func `starting cash of a new experiment is its cash`() throws {
        #expect(try Experiment(cashBalance: Money(1000)).startingCash == Money(1000))
    }

    @Test func `starting cash adds back what purchases cost`() throws {
        let experiment = try Experiment(cashBalance: Money(1000))
            .purchasing(makePurchase(shares: 3, price: "316.9961"), at: Self.now)

        #expect(experiment.startingCash == Money(1000))
    }

    @Test func `starting cash takes out sell fill proceeds`() throws {
        let order = try makeLimitOrder(shares: 4, limitPrice: "12.5")
        let experiment = try experimentWithPurchase(shares: 10)
            .placing(order)
            .filling(orderID: order.id, on: "2026-10-23")

        #expect(experiment.startingCash == Money(1000))
    }

    @Test func `starting cash ignores open, cancelled and filled buy orders`() throws {
        let open = try makeBuyLimitOrder(shares: 4, limitPrice: "9")
        let cancelled = try makeBuyLimitOrder(id: Self.secondBuyID, shares: 2, limitPrice: "9")
        let filled = try makeBuyLimitOrder(id: Self.thirdBuyID, shares: 3, limitPrice: "9")
        let experiment = try Experiment(cashBalance: Money(1000))
            .placing(open)
            .placing(cancelled)
            .placing(filled)
            .cancelling(orderID: cancelled.id, at: Self.now.addingTimeInterval(60))
            .fillingBuyOrder(orderID: filled.id, on: "2026-10-23")

        #expect(experiment.startingCash == Money(1000))
    }

    @Test func `held shares are all of a purchase with no sells`() throws {
        let experiment = try experimentWithPurchase(shares: 10)
        let purchase = try #require(experiment.purchases.first)

        #expect(experiment.heldShares(of: purchase) == 10)
    }

    @Test func `held shares leave out filled sells but not open or cancelled ones`() throws {
        let filled = try makeLimitOrder(shares: 4)
        let open = try makeLimitOrder(id: Self.secondSellID, shares: 2)
        let cancelled = try makeLimitOrder(id: Self.thirdSellID, shares: 1)
        let experiment = try experimentWithPurchase(shares: 10)
            .placing(filled)
            .placing(open)
            .placing(cancelled)
            .filling(orderID: filled.id, on: "2026-10-23")
            .cancelling(orderID: cancelled.id, at: Self.now.addingTimeInterval(60))
        let purchase = try #require(experiment.purchases.first)

        #expect(experiment.heldShares(of: purchase) == 6)
    }

    @Test func `invested cost of a fully held purchase is its cost`() throws {
        let purchase = try makePurchase(shares: 3, price: "316.9961")
        let experiment = try Experiment(cashBalance: Money(1000)).purchasing(purchase, at: Self.now)

        #expect(experiment.investedCost == purchase.cost)
    }

    @Test func `invested cost rounds each purchase to cents before summing`() throws {
        // Each costs 10.125, which rounds to 10.12; summing first gives 20.25.
        let first = try makePurchase(shares: 1, price: "10.125")
        let second = try makePurchase(id: Self.secondPurchaseID, shares: 1, price: "10.125")
        let experiment = try Experiment(cashBalance: Money(100))
            .purchasing(first, at: Self.now)
            .purchasing(second, at: Self.now)

        #expect(try experiment.investedCost == Money(#require(Decimal(string: "20.24"))))
    }

    @Test func `invested cost counts only held shares`() throws {
        let order = try makeLimitOrder(shares: 4, limitPrice: "12.5")
        let experiment = try experimentWithPurchase(shares: 10)
            .placing(order)
            .filling(orderID: order.id, on: "2026-10-23")

        #expect(experiment.investedCost == Money(60))
    }

    @Test func `invested cost includes buy order fills`() throws {
        let order = try makeBuyLimitOrder(shares: 3, limitPrice: "9")
        let experiment = try Experiment(cashBalance: Money(100))
            .placing(order)
            .fillingBuyOrder(orderID: order.id, on: "2026-10-23")

        #expect(experiment.investedCost == Money(27))
    }

    @Test func `invested cost of an experiment with no purchases is zero`() throws {
        #expect(try Experiment(cashBalance: Money(100)).investedCost == .zero)
    }

    private static let now = Date(timeIntervalSince1970: 1_793_000_000)
    private static let secondPurchaseID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let secondSellID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
    private static let thirdSellID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!
    private static let secondBuyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    private static let thirdBuyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B3")!

    private func experimentWithPurchase(shares: Int) throws -> Experiment {
        try Experiment(cashBalance: Money(1000)).purchasing(makePurchase(shares: shares, price: "10"), at: Self.now)
    }
}
