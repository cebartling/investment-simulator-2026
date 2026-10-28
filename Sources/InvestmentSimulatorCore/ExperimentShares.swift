import Foundation

/// A purchase's shares: which are free, and selling them at a quote
/// (ADR-0016).
public extension Experiment {
    /// The shares of `purchase` neither sold, by a sale or a filled order,
    /// nor reserved by an order open at `date`. Sold shares are gone
    /// whatever the date.
    func availableShares(of purchase: Purchase, at date: Date) -> Int {
        let ordered = limitOrders
            .filter { $0.purchaseID == purchase.id && ($0.filledOn != nil || $0.isOpen(at: date)) }
            .map(\.shares)
            .reduce(0, +)
        let sold = sales
            .filter { $0.purchaseID == purchase.id }
            .map(\.shares)
            .reduce(0, +)
        return purchase.shares - ordered - sold
    }

    /// The experiment after `sale`, its proceeds added to cash. It can sell
    /// only shares available when it is made.
    func selling(_ sale: Sale) throws(ExperimentError) -> Experiment {
        try recording(sale, cashBalance: cashBalance + sale.proceeds)
    }
}

extension Experiment {
    /// A step a rebuilt experiment takes again to check its shares.
    enum ShareStep {
        case placing(LimitOrder)
        case selling(Sale)
    }

    /// The sell placements and sales in time order. At the same time,
    /// placements come first, then sales, each in saved order. Either way
    /// gives the same result: at one instant an open order and a sale each
    /// count the other's shares as taken.
    static func shareSteps(limitOrders: [LimitOrder], sales: [Sale]) -> [ShareStep] {
        let placements = limitOrders.enumerated().map { index, order in
            (date: order.placedAt, kind: 0, index: index, step: ShareStep.placing(order))
        }
        let sold = sales.enumerated().map { index, sale in
            (date: sale.soldAt, kind: 1, index: index, step: ShareStep.selling(sale))
        }
        return (placements + sold)
            .sorted { ($0.date, $0.kind, $0.index) < ($1.date, $1.kind, $1.index) }
            .map(\.step)
    }

    /// The experiment with `sale` recorded and its cash set to
    /// `cashBalance`. The sale must be of a known purchase's available
    /// shares. Rebuilding an experiment keeps its cash, since the saved
    /// balance already includes the sale.
    func recording(_ sale: Sale, cashBalance: Money) throws(ExperimentError) -> Experiment {
        guard let purchase = purchases.first(where: { $0.id == sale.purchaseID }) else {
            throw .unknownPurchase(sale.purchaseID)
        }
        let available = availableShares(of: purchase, at: sale.soldAt)
        guard sale.shares <= available else {
            throw .insufficientShares(requested: sale.shares, available: available)
        }
        return Experiment(
            validCashBalance: cashBalance,
            purchases: purchases,
            limitOrders: limitOrders,
            buyLimitOrders: buyLimitOrders,
            sales: sales + [sale],
            name: name,
            notes: notes,
            createdAt: createdAt,
        )
    }
}
