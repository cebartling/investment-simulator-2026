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

    /// What the shares still held of `ticker` cost, each purchase rounded
    /// to cents as `investedCost` rounds them, so every ticker's cost adds
    /// up to it exactly (PIN-511).
    func investedCost(of ticker: Ticker) -> Money {
        purchases
            .filter { $0.ticker == ticker }
            .map { $0.cost(of: heldShares(of: $0)) }
            .reduce(.zero, +)
    }

    /// The shares still held of `ticker` at `price` a share, rounded to
    /// cents. Rounded for each ticker, so the tickers' values can add up to
    /// a cent or so off `marketValue(prices:)`, which rounds once.
    func marketValue(of ticker: Ticker, at price: Decimal) -> Money {
        Money(price).times(heldShares(of: ticker)).roundedToCents()
    }

    /// The market value of `ticker` at `price` against what its held shares
    /// cost. No percent when that cost is zero.
    func unrealizedGain(of ticker: Ticker, at price: Decimal) -> Gain {
        let cost = investedCost(of: ticker)
        return Gain(amount: marketValue(of: ticker, at: price) - cost, base: cost)
    }
}
