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

    /// The tickers with shares still held: the ones the market value needs
    /// prices for.
    var heldTickers: Set<Ticker> {
        Set(purchases.filter { heldShares(of: $0) > 0 }.map(\.ticker))
    }

    /// The held shares at `prices`, a price per share for each ticker,
    /// rounded to cents. Nil unless every held ticker has a price.
    func marketValue(prices: [Ticker: Decimal]) -> Money? {
        var values: [Money] = []
        for purchase in purchases {
            let shares = heldShares(of: purchase)
            guard shares > 0 else {
                continue
            }
            guard let price = prices[purchase.ticker] else {
                return nil
            }
            values.append(Money(price).times(shares))
        }
        return values.reduce(.zero, +).roundedToCents()
    }

    /// The cash plus the market value at `prices`. Nil unless every held
    /// ticker has a price.
    func totalValue(prices: [Ticker: Decimal]) -> Money? {
        marketValue(prices: prices).map { cashBalance + $0 }
    }

    /// The total value at `prices` against the starting cash. Nil unless
    /// every held ticker has a price.
    func gain(prices: [Ticker: Decimal]) -> Gain? {
        totalValue(prices: prices).map { Gain(amount: $0 - startingCash, startingCash: startingCash) }
    }
}

/// How far an experiment's total value is from its starting cash.
public struct Gain: Sendable, Hashable {
    /// Negative for a loss.
    public let amount: Money
    /// The amount as a percent of the starting cash, unrounded, such as 2.5
    /// for 2.5%. Nil when the experiment started with no cash.
    public let percent: Decimal?

    init(amount: Money, startingCash: Money) {
        self.amount = amount
        percent = startingCash == .zero ? nil : amount.amount / startingCash.amount * 100
    }
}
