import Foundation

/// The figures the Experiment header reports (PIN-408). None is stored:
/// each is derived from the cash, purchases and orders.
public extension Experiment {
    /// The cash the experiment started with: the balance plus what every
    /// purchase cost, less every sell fill's proceeds. Open and cancelled
    /// orders moved no cash, and a buy fill is one of the purchases.
    var startingCash: Money {
        let spent = purchases.map(\.cost).reduce(.zero, +)
        let received = limitOrders.filter { $0.filledOn != nil }.map(\.proceeds).reduce(.zero, +)
        return cashBalance + spent - received
    }

    /// The shares of `purchase` still held: all but those filled sell orders
    /// sold. Unlike `availableShares(of:at:)`, shares an open order reserves
    /// still count.
    func heldShares(of purchase: Purchase) -> Int {
        let sold = limitOrders
            .filter { $0.purchaseID == purchase.id && $0.filledOn != nil }
            .map(\.shares)
            .reduce(0, +)
        return purchase.shares - sold
    }

    /// What the shares still held cost: for each purchase, its held shares
    /// times its price, rounded to cents, so a fully held purchase matches
    /// its cost. Then summed.
    var investedCost: Money {
        purchases
            .map { Money($0.pricePerShare).times(heldShares(of: $0)).roundedToCents() }
            .reduce(.zero, +)
    }
}
