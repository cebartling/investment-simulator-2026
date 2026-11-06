import Foundation

/// What an experiment holds of one ticker, for its stock card (PIN-510).
/// Like the header's figures, none of it is stored.
public extension Experiment {
    /// The shares still held of every purchase of `ticker`
    /// (`heldShares(of:)` for a purchase), added up.
    func heldShares(of ticker: Ticker) -> Int {
        purchases
            .filter { $0.ticker == ticker }
            .map { heldShares(of: $0) }
            .reduce(0, +)
    }

    /// The price paid per share still held of `ticker`: each purchase's
    /// price weighed by its held shares. Unrounded, like a quoted price, so
    /// one purchase's average is exactly its price. Nil with none held.
    func averagePrice(of ticker: Ticker) -> Decimal? {
        let held = heldShares(of: ticker)
        guard held > 0 else {
            return nil
        }
        let paid = purchases
            .filter { $0.ticker == ticker }
            .map { $0.pricePerShare * Decimal(heldShares(of: $0)) }
            .reduce(0, +)
        return paid / Decimal(held)
    }
}
