import Foundation
import InvestmentSimulatorCore
import Testing

struct ExperimentTests {
    @Test(arguments: ["0", "0.01", "10000", "1234567.89"])
    func `experiment starts with a non-negative cash balance`(amount: String) throws {
        let cashBalance = try Money(#require(Decimal(string: amount)))

        let experiment = try Experiment(cashBalance: cashBalance)

        #expect(experiment.cashBalance == cashBalance)
    }

    @Test func `empty experiment has a zero cash balance`() {
        #expect(Experiment.empty.cashBalance == .zero)
    }

    @Test func `negative cash balance is rejected`() throws {
        let cashBalance = try Money(#require(Decimal(string: "-0.01")))

        #expect(throws: ExperimentError.negativeCashBalance(cashBalance)) {
            try Experiment(cashBalance: cashBalance)
        }
    }

    @Test func `new experiment has no purchases`() throws {
        #expect(try Experiment(cashBalance: Money(100)).purchases.isEmpty)
        #expect(Experiment.empty.purchases.isEmpty)
    }

    @Test func `purchasing deducts the cost and records the purchase`() throws {
        let experiment = try Experiment(cashBalance: Money(1000))
        let purchase = try makePurchase(shares: 2, price: "250.10")

        let updated = try experiment.purchasing(purchase)

        #expect(try updated.cashBalance == Money(#require(Decimal(string: "499.80"))))
        #expect(updated.purchases == [purchase])
    }

    @Test func `repeat purchases of a ticker are kept separately`() throws {
        let first = try makePurchase(shares: 1, price: "10")
        let second = try makePurchase(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            shares: 1,
            price: "12",
        )

        let updated = try Experiment(cashBalance: Money(100)).purchasing(first).purchasing(second)

        #expect(updated.purchases == [first, second])
        #expect(updated.cashBalance == Money(78))
    }

    @Test func `purchase can spend all the cash`() throws {
        let updated = try Experiment(cashBalance: Money(20)).purchasing(makePurchase(shares: 2, price: "10"))

        #expect(updated.cashBalance == .zero)
    }

    @Test func `purchase costing more than the cash is rejected`() throws {
        let experiment = try Experiment(cashBalance: Money(19))

        #expect(throws: ExperimentError.insufficientCash(cost: Money(20), available: Money(19))) {
            try experiment.purchasing(makePurchase(shares: 2, price: "10"))
        }
    }

    @Test func `experiment keeps the purchases it is created with`() throws {
        let purchase = try makePurchase(shares: 1, price: "10")

        let experiment = try Experiment(cashBalance: Money(5), purchases: [purchase])

        #expect(experiment.purchases == [purchase])
    }
}

struct ExperimentLimitOrderTests {
    @Test func `new experiment has no limit orders`() throws {
        #expect(try Experiment(cashBalance: Money(100)).limitOrders.isEmpty)
        #expect(Experiment.empty.limitOrders.isEmpty)
    }

    @Test func `placing an order records it without touching cash or purchases`() throws {
        let experiment = try experimentWithPurchase(shares: 10)
        let order = try makeLimitOrder(shares: 4)

        let updated = try experiment.placing(order)

        #expect(updated.limitOrders == [order])
        #expect(updated.cashBalance == experiment.cashBalance)
        #expect(updated.purchases == experiment.purchases)
    }

    @Test func `open orders reserve their shares`() throws {
        let experiment = try experimentWithPurchase(shares: 10)
        let purchase = try #require(experiment.purchases.first)

        let updated = try experiment.placing(makeLimitOrder(shares: 4))

        #expect(experiment.availableShares(of: purchase, at: Self.now) == 10)
        #expect(updated.availableShares(of: purchase, at: Self.now) == 6)
    }

    @Test func `expired orders release their shares`() throws {
        let order = try makeLimitOrder(shares: 4)
        let updated = try experimentWithPurchase(shares: 10).placing(order)
        let purchase = try #require(updated.purchases.first)

        #expect(updated.availableShares(of: purchase, at: order.expiresAt) == 10)
    }

    @Test func `order can sell every unreserved share`() throws {
        let updated = try experimentWithPurchase(shares: 10)
            .placing(makeLimitOrder(shares: 4))
            .placing(makeLimitOrder(id: Self.secondOrderID, shares: 6))

        #expect(updated.limitOrders.count == 2)
    }

    @Test func `order for more than the unreserved shares is rejected`() throws {
        let experiment = try experimentWithPurchase(shares: 10).placing(makeLimitOrder(shares: 4))

        #expect(throws: ExperimentError.insufficientShares(requested: 7, available: 6)) {
            try experiment.placing(makeLimitOrder(id: Self.secondOrderID, shares: 7))
        }
    }

    @Test func `order can reuse shares an expired order released`() throws {
        let first = try makeLimitOrder(shares: 10)
        let second = try makeLimitOrder(id: Self.secondOrderID, shares: 10, placedAt: first.expiresAt)

        let updated = try experimentWithPurchase(shares: 10).placing(first).placing(second)

        #expect(updated.limitOrders == [first, second])
    }

    @Test func `order for an unknown purchase is rejected`() throws {
        let purchaseID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000099"))

        #expect(throws: ExperimentError.unknownPurchase(purchaseID)) {
            try experimentWithPurchase(shares: 10).placing(makeLimitOrder(purchaseID: purchaseID))
        }
        #expect(throws: ExperimentError.unknownPurchase(purchaseID)) {
            try Experiment(cashBalance: .zero, limitOrders: [makeLimitOrder(purchaseID: purchaseID)])
        }
    }

    @Test func `purchasing keeps the limit orders`() throws {
        let order = try makeLimitOrder()
        let experiment = try experimentWithPurchase(shares: 10).placing(order)

        let updated = try experiment.purchasing(makePurchase(id: Self.secondPurchaseID, shares: 1, price: "1"))

        #expect(updated.limitOrders == [order])
    }

    private static let now = Date(timeIntervalSince1970: 1_793_000_000)
    private static let secondOrderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
    private static let secondPurchaseID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private func experimentWithPurchase(shares: Int) throws -> Experiment {
        try Experiment(cashBalance: Money(1000)).purchasing(makePurchase(shares: shares, price: "10"))
    }
}
