import Foundation

/// One investment experiment, saved as one `.invsim` document (ADR-0005,
/// where it is called a scenario). It starts with a cash balance, buys
/// investments from it, and places limit orders to sell them, whose fills
/// add to the cash, and to buy more, whose fills become purchases.
public struct Experiment: Sendable, Hashable {
    /// A new experiment with no cash yet.
    public static let empty = Experiment(
        validCashBalance: .zero,
        purchases: [],
        limitOrders: [],
        buyLimitOrders: [],
    )

    /// The cash left after every purchase and buy fill, plus every sell
    /// fill's proceeds. Open buy orders reserve part of it.
    public let cashBalance: Money
    /// In the order they were made.
    public let purchases: [Purchase]
    /// In the order they were placed, including filled and expired ones.
    public let limitOrders: [LimitOrder]
    /// In the order they were placed, including filled, expired and
    /// cancelled ones (ADR-0014).
    public let buyLimitOrders: [BuyLimitOrder]

    public init(
        cashBalance: Money,
        purchases: [Purchase] = [],
        limitOrders: [LimitOrder] = [],
        buyLimitOrders: [BuyLimitOrder] = [],
    ) throws(ExperimentError) {
        guard cashBalance.amount >= 0 else {
            throw .negativeCashBalance(cashBalance)
        }
        try Self.checkFillPurchases(purchases: purchases, buyLimitOrders: buyLimitOrders)
        try Self.checkUniqueIDs(purchases: purchases, limitOrders: limitOrders, buyLimitOrders: buyLimitOrders)
        // Sell orders are placed again in their saved order, so each one
        // passes the same checks it passed when it was first placed. Buy
        // orders can't be: the balance is the one after every fill, not the
        // one each order was placed against.
        var experiment = Experiment(
            validCashBalance: cashBalance,
            purchases: purchases,
            limitOrders: [],
            buyLimitOrders: buyLimitOrders,
        )
        for order in limitOrders {
            experiment = try experiment.placing(order)
        }
        self = experiment
    }

    private init(
        validCashBalance cashBalance: Money,
        purchases: [Purchase],
        limitOrders: [LimitOrder],
        buyLimitOrders: [BuyLimitOrder],
    ) {
        self.cashBalance = cashBalance
        self.purchases = purchases
        self.limitOrders = limitOrders
        self.buyLimitOrders = buyLimitOrders
    }

    /// No two purchases or orders share an id, apart from a filled buy order
    /// and the purchase its fill made, which checkFillPurchases pairs.
    private static func checkUniqueIDs(
        purchases: [Purchase],
        limitOrders: [LimitOrder],
        buyLimitOrders: [BuyLimitOrder],
    ) throws(ExperimentError) {
        let unfilledBuyIDs = buyLimitOrders.filter { $0.filledOn == nil }.map(\.id)
        var seen = Set<UUID>()
        var seenBuy = Set<UUID>()
        for id in purchases.map(\.id) + limitOrders.map(\.id) + unfilledBuyIDs {
            guard seen.insert(id).inserted else {
                throw .duplicateID(id)
            }
        }
        for id in buyLimitOrders.map(\.id) {
            guard seenBuy.insert(id).inserted else {
                throw .duplicateID(id)
            }
        }
    }

    /// Each filled buy order has its purchase, exactly the one its fill
    /// makes, and every other buy order and purchase has none.
    private static func checkFillPurchases(
        purchases: [Purchase],
        buyLimitOrders: [BuyLimitOrder],
    ) throws(ExperimentError) {
        let fills = Dictionary(
            purchases.compactMap { purchase -> (UUID, Purchase)? in
                guard case .limitOrderFill = purchase.priceSource else {
                    return nil
                }
                return (purchase.id, purchase)
            },
            uniquingKeysWith: { first, _ in first },
        )
        let purchaseIDs = Set(purchases.map(\.id))
        for order in buyLimitOrders {
            let matches = if let filledOn = order.filledOn {
                fills[order.id] == (try? order.purchase(filledOn: filledOn))
            } else {
                !purchaseIDs.contains(order.id)
            }
            guard matches else {
                throw .mismatchedFillPurchase(order.id)
            }
        }
        let filledIDs = Set(buyLimitOrders.filter { $0.filledOn != nil }.map(\.id))
        if let orphan = fills.keys.first(where: { !filledIDs.contains($0) }) {
            throw .mismatchedFillPurchase(orphan)
        }
    }

    /// The cash held by buy orders open at `date`.
    public func reservedCash(at date: Date) -> Money {
        buyLimitOrders
            .filter { $0.isOpen(at: date) }
            .map(\.cost)
            .reduce(.zero, +)
    }

    /// The cash a purchase or a new buy order can spend at `date`: the
    /// balance less what open buy orders reserve.
    public func availableCash(at date: Date) -> Money {
        cashBalance - reservedCash(at: date)
    }

    /// The experiment after buying `purchase` at `date` with its cash. Cash
    /// never goes negative and reserved cash stays reserved, so a purchase
    /// costing more than the available cash is rejected.
    public func purchasing(_ purchase: Purchase, at date: Date) throws(ExperimentError) -> Experiment {
        let available = availableCash(at: date)
        guard purchase.cost <= available else {
            throw .insufficientCash(cost: purchase.cost, available: available)
        }
        return Experiment(
            validCashBalance: cashBalance - purchase.cost,
            purchases: purchases + [purchase],
            limitOrders: limitOrders,
            buyLimitOrders: buyLimitOrders,
        )
    }

    /// The experiment with the buy order `order` placed, reserving its cost.
    /// The cost must fit in the cash available when it is placed.
    public func placing(_ order: BuyLimitOrder) throws(ExperimentError) -> Experiment {
        let available = availableCash(at: order.placedAt)
        guard order.cost <= available else {
            throw .insufficientCash(cost: order.cost, available: available)
        }
        return Experiment(
            validCashBalance: cashBalance,
            purchases: purchases,
            limitOrders: limitOrders,
            buyLimitOrders: buyLimitOrders + [order],
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
        return Experiment(
            validCashBalance: cashBalance,
            purchases: purchases,
            limitOrders: limitOrders + [order],
            buyLimitOrders: buyLimitOrders,
        )
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
        guard order.cancelledAt == nil else {
            throw .orderCancelled(orderID)
        }
        var orders = limitOrders
        do {
            orders[index] = try order.filled(on: sessionDate)
        } catch {
            throw .invalidSessionDate(sessionDate)
        }
        return Experiment(
            validCashBalance: cashBalance + order.proceeds,
            purchases: purchases,
            limitOrders: orders,
            buyLimitOrders: buyLimitOrders,
        )
    }

    /// The experiment with the buy order `orderID` filled at its limit price
    /// in the session on `sessionDate`: its cost leaves cash and its purchase
    /// is added. Whether that session can fill the order is the caller's
    /// rule.
    public func fillingBuyOrder(orderID: UUID, on sessionDate: String) throws(ExperimentError) -> Experiment {
        guard let index = buyLimitOrders.firstIndex(where: { $0.id == orderID }) else {
            throw .unknownOrder(orderID)
        }
        let order = buyLimitOrders[index]
        guard order.filledOn == nil else {
            throw .orderAlreadyFilled(orderID)
        }
        guard order.cancelledAt == nil else {
            throw .orderCancelled(orderID)
        }
        // An unfilled order's cost is still reserved, so it is never short.
        guard order.cost <= cashBalance else {
            throw .insufficientCash(cost: order.cost, available: cashBalance)
        }
        var orders = buyLimitOrders
        let purchase: Purchase
        do {
            orders[index] = try order.filled(on: sessionDate)
            purchase = try order.purchase(filledOn: sessionDate)
        } catch {
            throw .invalidSessionDate(sessionDate)
        }
        return Experiment(
            validCashBalance: cashBalance - order.cost,
            purchases: purchases + [purchase],
            limitOrders: limitOrders,
            buyLimitOrders: orders,
        )
    }

    /// The experiment with the order `orderID`, sell or buy, cancelled at
    /// `date`, freeing its shares or cash. Only an order open then can be
    /// cancelled.
    public func cancelling(orderID: UUID, at date: Date) throws(ExperimentError) -> Experiment {
        if let index = limitOrders.firstIndex(where: { $0.id == orderID }) {
            guard limitOrders[index].isOpen(at: date) else {
                throw .orderNotOpen(orderID)
            }
            var orders = limitOrders
            orders[index] = Self.cancel(orders[index], at: date)
            return Experiment(
                validCashBalance: cashBalance,
                purchases: purchases,
                limitOrders: orders,
                buyLimitOrders: buyLimitOrders,
            )
        }
        guard let index = buyLimitOrders.firstIndex(where: { $0.id == orderID }) else {
            throw .unknownOrder(orderID)
        }
        guard buyLimitOrders[index].isOpen(at: date) else {
            throw .orderNotOpen(orderID)
        }
        var orders = buyLimitOrders
        orders[index] = Self.cancel(orders[index], at: date)
        return Experiment(
            validCashBalance: cashBalance,
            purchases: purchases,
            limitOrders: limitOrders,
            buyLimitOrders: orders,
        )
    }

    private static func cancel(_ order: LimitOrder, at date: Date) -> LimitOrder {
        do {
            return try order.cancelled(at: date)
        } catch {
            preconditionFailure("An open limit order couldn't be cancelled: \(error)")
        }
    }

    private static func cancel(_ order: BuyLimitOrder, at date: Date) -> BuyLimitOrder {
        do {
            return try order.cancelled(at: date)
        } catch {
            preconditionFailure("An open buy limit order couldn't be cancelled: \(error)")
        }
    }
}

public enum ExperimentError: Error, Equatable {
    case negativeCashBalance(Money)
    case insufficientCash(cost: Money, available: Money)
    case unknownPurchase(UUID)
    case insufficientShares(requested: Int, available: Int)
    case unknownOrder(UUID)
    case orderAlreadyFilled(UUID)
    case orderCancelled(UUID)
    /// The order has filled, expired or been cancelled.
    case orderNotOpen(UUID)
    case invalidSessionDate(String)
    /// A filled buy order without its purchase, or a purchase marked as a
    /// fill without its filled buy order.
    case mismatchedFillPurchase(UUID)
    /// Two purchases or orders share an id. A filled buy order and its
    /// purchase are the one pair that shares one.
    case duplicateID(UUID)
}
