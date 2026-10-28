import Foundation

/// Where a purchase's price came from.
public enum PriceSource: Sendable, Hashable {
    /// An intraday quote; `delayed` when the plan's quotes lag the market.
    case liveQuote(delayed: Bool)
    /// The settled close of the session on `sessionDate` (`yyyy-MM-dd`).
    case close(sessionDate: String)
    /// A buy limit order filled at its limit price in the session on
    /// `sessionDate` (`yyyy-MM-dd`, ADR-0014).
    case limitOrderFill(sessionDate: String)
}

/// One purchase of a whole number of shares at a quoted price. Buying the
/// same ticker again is a separate purchase.
public struct Purchase: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let ticker: Ticker
    public let shares: Int
    /// As quoted, which can include fractions of a cent.
    public let pricePerShare: Decimal
    public let pricedAt: Date
    public let priceSource: PriceSource

    public init(
        id: UUID,
        ticker: Ticker,
        shares: Int,
        pricePerShare: Decimal,
        pricedAt: Date,
        priceSource: PriceSource,
    ) throws(PurchaseError) {
        guard shares > 0 else {
            throw .nonPositiveShares(shares)
        }
        guard pricePerShare > 0 else {
            throw .nonPositivePrice(pricePerShare)
        }
        self.id = id
        self.ticker = ticker
        self.shares = shares
        self.pricePerShare = pricePerShare
        self.pricedAt = pricedAt
        self.priceSource = priceSource
    }

    /// Price times shares, rounded to cents: what the purchase takes from cash.
    public var cost: Money {
        cost(of: shares)
    }

    /// What `shares` of the purchase cost: price times shares, rounded to
    /// cents. A sale's realized gain subtracts it (ADR-0016). Rounded on its
    /// own, so the costs of a purchase sold in pieces can sum to a cent more
    /// or less than `cost`.
    public func cost(of shares: Int) -> Money {
        Money(pricePerShare).times(shares).roundedToCents()
    }
}

public enum PurchaseError: Error, Equatable {
    case nonPositiveShares(Int)
    case nonPositivePrice(Decimal)
}
