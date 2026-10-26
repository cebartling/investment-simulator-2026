import Foundation

/// One investment experiment, saved as one `.invsim` document (ADR-0005,
/// where it is called a scenario). It starts with a cash balance, buys
/// investments from it, and places limit orders to sell them, whose fills
/// add to the cash.
public struct Experiment: Sendable, Hashable {
    /// A new experiment with no cash yet.
    public static let empty = Experiment(validCashBalance: .zero, purchases: [], limitOrders: [])

    /// The cash left after every purchase, plus every fill's proceeds.
    public let cashBalance: Money
    /// In the order they were made.
    public let purchases: [Purchase]
    /// In the order they were placed, including filled and expired ones.
    public let limitOrders: [LimitOrder]

    public init(
        cashBalance: Money,
        purchases: [Purchase] = [],
        limitOrders: [LimitOrder] = [],
    ) throws(ExperimentError) {
        guard cashBalance.amount >= 0 else {
            throw .negativeCashBalance(cashBalance)
        }
        // Orders are placed again in their saved order, so each one passes
        // the same checks it passed when it was first placed.
        var experiment = Experiment(validCashBalance: cashBalance, purchases: purchases, limitOrders: [])
        for order in limitOrders {
            experiment = try experiment.placing(order)
        }
        self = experiment
    }

    private init(validCashBalance cashBalance: Money, purchases: [Purchase], limitOrders: [LimitOrder]) {
        self.cashBalance = cashBalance
        self.purchases = purchases
        self.limitOrders = limitOrders
    }

    /// The experiment after buying `purchase` with its cash. Cash never goes
    /// negative, so a purchase costing more than the balance is rejected.
    public func purchasing(_ purchase: Purchase) throws(ExperimentError) -> Experiment {
        guard purchase.cost <= cashBalance else {
            throw .insufficientCash(cost: purchase.cost, available: cashBalance)
        }
        return Experiment(
            validCashBalance: cashBalance - purchase.cost,
            purchases: purchases + [purchase],
            limitOrders: limitOrders,
        )
    }

    /// The shares of `purchase` neither sold by a filled order nor reserved
    /// by an order open at `date`.
    public func availableShares(of purchase: Purchase, at date: Date) -> Int {
        let unavailable = limitOrders
            .filter { $0.purchaseID == purchase.id && ($0.filledOn != nil || $0.isOpen(at: date)) }
            .map(\.shares)
            .reduce(0, +)
        return purchase.shares - unavailable
    }

    /// The experiment with `order` placed. Its shares must be unreserved
    /// when it is placed. Cash and purchases don't change.
    public func placing(_ order: LimitOrder) throws(ExperimentError) -> Experiment {
        guard let purchase = purchases.first(where: { $0.id == order.purchaseID }) else {
            throw .unknownPurchase(order.purchaseID)
        }
        let available = availableShares(of: purchase, at: order.placedAt)
        guard order.shares <= available else {
            throw .insufficientShares(requested: order.shares, available: available)
        }
        return Experiment(validCashBalance: cashBalance, purchases: purchases, limitOrders: limitOrders + [order])
    }

    /// The experiment with the order `orderID` filled at its limit price in
    /// the session on `sessionDate`, and its proceeds added to cash. Whether
    /// that session can fill the order is the caller's rule.
    public func filling(orderID: UUID, on sessionDate: String) throws(ExperimentError) -> Experiment {
        guard let index = limitOrders.firstIndex(where: { $0.id == orderID }) else {
            throw .unknownOrder(orderID)
        }
        let order = limitOrders[index]
        guard order.filledOn == nil else {
            throw .orderAlreadyFilled(orderID)
        }
        var orders = limitOrders
        do {
            orders[index] = try order.filled(on: sessionDate)
        } catch {
            throw .invalidSessionDate(sessionDate)
        }
        return Experiment(validCashBalance: cashBalance + order.proceeds, purchases: purchases, limitOrders: orders)
    }
}

public enum ExperimentError: Error, Equatable {
    case negativeCashBalance(Money)
    case insufficientCash(cost: Money, available: Money)
    case unknownPurchase(UUID)
    case insufficientShares(requested: Int, available: Int)
    case unknownOrder(UUID)
    case orderAlreadyFilled(UUID)
    case invalidSessionDate(String)
}
