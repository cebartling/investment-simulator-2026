import Foundation
import InvestmentSimulatorCore
import Testing

struct ExperimentBuyLimitOrderTests {
    @Test func `new experiment has no buy limit orders`() throws {
        #expect(try Experiment(cashBalance: Money(100)).buyLimitOrders.isEmpty)
        #expect(Experiment.empty.buyLimitOrders.isEmpty)
    }

    @Test func `placing a buy order records it and reserves its cost`() throws {
        let experiment = try Experiment(cashBalance: Money(100))
        let order = try makeBuyLimitOrder(shares: 4, limitPrice: "9")

        let updated = try experiment.placing(order)

        #expect(updated.buyLimitOrders == [order])
        #expect(updated.cashBalance == Money(100))
        #expect(updated.reservedCash(at: Self.now) == Money(36))
        #expect(updated.availableCash(at: Self.now) == Money(64))
    }

    @Test func `buy order can reserve all the available cash`() throws {
        let updated = try Experiment(cashBalance: Money(36)).placing(makeBuyLimitOrder(shares: 4, limitPrice: "9"))

        #expect(updated.availableCash(at: Self.now) == .zero)
    }

    @Test func `buy order costing more than the available cash is rejected`() throws {
        let experiment = try Experiment(cashBalance: Money(100)).placing(makeBuyLimitOrder(shares: 4, limitPrice: "9"))

        #expect(throws: ExperimentError.insufficientCash(cost: Money(72), available: Money(64))) {
            try experiment.placing(makeBuyLimitOrder(id: Self.secondOrderID, shares: 8, limitPrice: "9"))
        }
    }

    @Test func `purchase can't spend cash reserved by an open buy order`() throws {
        let experiment = try Experiment(cashBalance: Money(100)).placing(makeBuyLimitOrder(shares: 4, limitPrice: "9"))

        #expect(throws: ExperimentError.insufficientCash(cost: Money(70), available: Money(64))) {
            try experiment.purchasing(makePurchase(shares: 7, price: "10"), at: Self.now)
        }
    }

    @Test func `expired buy orders release their cash`() throws {
        let order = try makeBuyLimitOrder(shares: 4, limitPrice: "9")
        let experiment = try Experiment(cashBalance: Money(100)).placing(order)

        #expect(experiment.availableCash(at: order.expiresAt) == Money(100))
        let purchase = try makePurchase(shares: 10, price: "10")
        #expect(try experiment.purchasing(purchase, at: order.expiresAt).cashBalance == .zero)
    }

    @Test func `filling a buy order spends its cost and adds its purchase`() throws {
        let order = try makeBuyLimitOrder(shares: 4, limitPrice: "9")
        let experiment = try Experiment(cashBalance: Money(100)).placing(order)

        let updated = try experiment.fillingBuyOrder(orderID: order.id, on: "2026-10-23")

        #expect(updated.cashBalance == Money(64))
        #expect(try updated.buyLimitOrders == [order.filled(on: "2026-10-23")])
        #expect(try updated.purchases == [order.purchase(filledOn: "2026-10-23")])
        #expect(updated.reservedCash(at: Self.now) == .zero)
        #expect(updated.availableCash(at: Self.now) == Money(64))
    }

    @Test func `a filled buy order's shares can be sold with a limit order`() throws {
        let order = try makeBuyLimitOrder(shares: 4, limitPrice: "9")
        let filled = try Experiment(cashBalance: Money(100)).placing(order).fillingBuyOrder(
            orderID: order.id,
            on: "2026-10-23",
        )

        let updated = try filled.placing(makeLimitOrder(purchaseID: order.id, shares: 4))

        #expect(updated.limitOrders.count == 1)
    }

    @Test func `filling an unknown buy order is rejected`() throws {
        #expect(throws: ExperimentError.unknownOrder(Self.secondOrderID)) {
            try Experiment(cashBalance: Money(100)).fillingBuyOrder(orderID: Self.secondOrderID, on: "2026-10-23")
        }
    }

    @Test func `filling a buy order twice is rejected`() throws {
        let order = try makeBuyLimitOrder()
        let filled = try Experiment(cashBalance: Money(100)).placing(order).fillingBuyOrder(
            orderID: order.id,
            on: "2026-10-23",
        )

        #expect(throws: ExperimentError.orderAlreadyFilled(order.id)) {
            try filled.fillingBuyOrder(orderID: order.id, on: "2026-10-24")
        }
    }

    @Test func `filling a cancelled buy order is rejected`() throws {
        let order = try makeBuyLimitOrder()
        let cancelled = try Experiment(cashBalance: Money(100))
            .placing(order)
            .cancelling(orderID: order.id, at: Self.now)

        #expect(throws: ExperimentError.orderCancelled(order.id)) {
            try cancelled.fillingBuyOrder(orderID: order.id, on: "2026-10-23")
        }
    }

    @Test func `filling a buy order with a malformed session date is rejected`() throws {
        let order = try makeBuyLimitOrder()
        let experiment = try Experiment(cashBalance: Money(100)).placing(order)

        #expect(throws: ExperimentError.invalidSessionDate("10/23/2026")) {
            try experiment.fillingBuyOrder(orderID: order.id, on: "10/23/2026")
        }
    }

    @Test func `cancelling a buy order frees its cash`() throws {
        let order = try makeBuyLimitOrder(shares: 4, limitPrice: "9")
        let cancelledAt = Self.now.addingTimeInterval(60)
        let experiment = try Experiment(cashBalance: Money(100)).placing(order)

        let updated = try experiment.cancelling(orderID: order.id, at: cancelledAt)

        #expect(try updated.buyLimitOrders == [order.cancelled(at: cancelledAt)])
        #expect(updated.availableCash(at: cancelledAt) == Money(100))
        #expect(updated.cashBalance == Money(100))
    }

    @Test func `experiment created with a filled buy order and its purchase is accepted`() throws {
        let order = try makeBuyLimitOrder(shares: 4, limitPrice: "9")
        let filled = try order.filled(on: "2026-10-23")

        let experiment = try Experiment(
            cashBalance: Money(64),
            purchases: [order.purchase(filledOn: "2026-10-23")],
            buyLimitOrders: [filled],
        )

        #expect(experiment.buyLimitOrders == [filled])
    }

    @Test func `experiment created with a filled buy order but no purchase is rejected`() throws {
        let filled = try makeBuyLimitOrder().filled(on: "2026-10-23")

        #expect(throws: ExperimentError.mismatchedFillPurchase(filled.id)) {
            try Experiment(cashBalance: Money(64), buyLimitOrders: [filled])
        }
    }

    @Test func `experiment created with a fill purchase from another session is rejected`() throws {
        let order = try makeBuyLimitOrder()

        #expect(throws: ExperimentError.mismatchedFillPurchase(order.id)) {
            try Experiment(
                cashBalance: Money(64),
                purchases: [order.purchase(filledOn: "2026-10-22")],
                buyLimitOrders: [order.filled(on: "2026-10-23")],
            )
        }
    }

    @Test func `experiment created with an unfilled buy order that has a purchase is rejected`() throws {
        let order = try makeBuyLimitOrder()

        #expect(throws: ExperimentError.mismatchedFillPurchase(order.id)) {
            try Experiment(
                cashBalance: Money(64),
                purchases: [order.purchase(filledOn: "2026-10-23")],
                buyLimitOrders: [order],
            )
        }
    }

    @Test func `experiment created with a fill purchase but no order is rejected`() throws {
        let purchase = try makeBuyLimitOrder().purchase(filledOn: "2026-10-23")

        #expect(throws: ExperimentError.mismatchedFillPurchase(purchase.id)) {
            try Experiment(cashBalance: Money(64), purchases: [purchase])
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_793_000_000)
    private static let secondOrderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
}

struct ExperimentCancellationTests {
    @Test func `cancelling a sell order frees its shares`() throws {
        let order = try makeLimitOrder(shares: 4)
        let cancelledAt = Self.now.addingTimeInterval(60)
        let experiment = try experimentWithPurchase().placing(order)
        let purchase = try #require(experiment.purchases.first)

        let updated = try experiment.cancelling(orderID: order.id, at: cancelledAt)

        #expect(try updated.limitOrders == [order.cancelled(at: cancelledAt)])
        #expect(updated.availableShares(of: purchase, at: Self.now) == 6)
        #expect(updated.availableShares(of: purchase, at: cancelledAt) == 10)
    }

    @Test func `freed shares can be sold again, and the experiment reopens`() throws {
        let order = try makeLimitOrder(shares: 10)
        let cancelledAt = Self.now.addingTimeInterval(60)
        let replacement = try makeLimitOrder(id: Self.secondOrderID, shares: 10, placedAt: cancelledAt)

        let updated = try experimentWithPurchase()
            .placing(order)
            .cancelling(orderID: order.id, at: cancelledAt)
            .placing(replacement)

        let reopened = try Experiment(
            cashBalance: updated.cashBalance,
            purchases: updated.purchases,
            limitOrders: updated.limitOrders,
        )
        #expect(reopened == updated)
    }

    @Test func `cancelling an unknown order is rejected`() throws {
        #expect(throws: ExperimentError.unknownOrder(Self.secondOrderID)) {
            try experimentWithPurchase().cancelling(orderID: Self.secondOrderID, at: Self.now)
        }
    }

    @Test func `cancelling a filled order is rejected`() throws {
        let order = try makeLimitOrder()
        let filled = try experimentWithPurchase().placing(order).filling(orderID: order.id, on: "2026-10-23")

        #expect(throws: ExperimentError.orderNotOpen(order.id)) {
            try filled.cancelling(orderID: order.id, at: Self.now)
        }
    }

    @Test func `cancelling an expired order is rejected`() throws {
        let order = try makeLimitOrder()
        let experiment = try experimentWithPurchase().placing(order)

        #expect(throws: ExperimentError.orderNotOpen(order.id)) {
            try experiment.cancelling(orderID: order.id, at: order.expiresAt)
        }
    }

    @Test func `cancelling an order twice is rejected`() throws {
        let order = try makeLimitOrder()
        let cancelled = try experimentWithPurchase().placing(order).cancelling(orderID: order.id, at: Self.now)

        #expect(throws: ExperimentError.orderNotOpen(order.id)) {
            try cancelled.cancelling(orderID: order.id, at: Self.now.addingTimeInterval(60))
        }
    }

    @Test func `filling a cancelled sell order is rejected`() throws {
        let order = try makeLimitOrder()
        let cancelled = try experimentWithPurchase().placing(order).cancelling(orderID: order.id, at: Self.now)

        #expect(throws: ExperimentError.orderCancelled(order.id)) {
            try cancelled.filling(orderID: order.id, on: "2026-10-23")
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_793_000_000)
    private static let secondOrderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!

    private func experimentWithPurchase() throws -> Experiment {
        try Experiment(cashBalance: Money(1000)).purchasing(makePurchase(shares: 10, price: "10"), at: Self.now)
    }
}
