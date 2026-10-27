import Foundation

/// An order to buy shares of a ticker once the price drops to `limitPrice`
/// (ADR-0014). It fills at exactly that price into a purchase, expires, or
/// is cancelled. While open it reserves its cost from the experiment's cash.
public struct BuyLimitOrder: Sendable, Hashable, Identifiable {
    /// Also the id of the purchase the order fills into.
    public let id: UUID
    public let ticker: Ticker
    public let shares: Int
    /// In whole cents.
    public let limitPrice: Money
    public let placedAt: Date
    public let expiresAt: Date
    /// The session (`yyyy-MM-dd`) the order filled in, or nil while unfilled.
    public let filledOn: String?
    /// When the order was cancelled, or nil if it wasn't.
    public let cancelledAt: Date?

    /// An order with a known expiry, fill and cancellation, such as one read
    /// from a file. New orders come from `placed(id:ticker:shares:limitPrice:at:)`.
    public init(
        id: UUID,
        ticker: Ticker,
        shares: Int,
        limitPrice: Money,
        placedAt: Date,
        expiresAt: Date,
        filledOn: String? = nil,
        cancelledAt: Date? = nil,
    ) throws(LimitOrderError) {
        guard shares > 0 else {
            throw .nonPositiveShares(shares)
        }
        guard limitPrice > .zero else {
            throw .nonPositivePrice(limitPrice)
        }
        if let filledOn, !isSessionDate(filledOn) {
            throw .invalidSessionDate(filledOn)
        }
        guard filledOn == nil || cancelledAt == nil else {
            throw .filledAndCancelled
        }
        self.id = id
        self.ticker = ticker
        self.shares = shares
        self.limitPrice = limitPrice
        self.placedAt = placedAt
        self.expiresAt = expiresAt
        self.filledOn = filledOn
        self.cancelledAt = cancelledAt
    }

    /// A new order placed at `placedAt`, expiring as a sell order placed then
    /// would.
    public static func placed(
        id: UUID,
        ticker: Ticker,
        shares: Int,
        limitPrice: Money,
        at placedAt: Date,
    ) throws(LimitOrderError) -> BuyLimitOrder {
        try BuyLimitOrder(
            id: id,
            ticker: ticker,
            shares: shares,
            limitPrice: limitPrice,
            placedAt: placedAt,
            expiresAt: LimitOrder.expiry(forPlacedAt: placedAt),
        )
    }

    /// True until the order fills, expires or is cancelled.
    public func isOpen(at date: Date) -> Bool {
        filledOn == nil && date < expiresAt && cancelledAt.map { date < $0 } ?? true
    }

    /// What the order reserves while open and takes from cash when it fills:
    /// the limit price times the shares.
    public var cost: Money {
        limitPrice.times(shares).roundedToCents()
    }

    /// The order filled at its limit price in the session on `sessionDate`.
    public func filled(on sessionDate: String) throws(LimitOrderError) -> BuyLimitOrder {
        try BuyLimitOrder(
            id: id,
            ticker: ticker,
            shares: shares,
            limitPrice: limitPrice,
            placedAt: placedAt,
            expiresAt: expiresAt,
            filledOn: sessionDate,
            cancelledAt: cancelledAt,
        )
    }

    /// The order cancelled at `date`. Its cash is free again from then.
    public func cancelled(at date: Date) throws(LimitOrderError) -> BuyLimitOrder {
        try BuyLimitOrder(
            id: id,
            ticker: ticker,
            shares: shares,
            limitPrice: limitPrice,
            placedAt: placedAt,
            expiresAt: expiresAt,
            filledOn: filledOn,
            cancelledAt: date,
        )
    }

    /// The purchase a fill in the session on `sessionDate` makes: the order's
    /// shares at its limit price, priced at that session's close.
    public func purchase(filledOn sessionDate: String) throws(LimitOrderError) -> Purchase {
        guard let close = sessionClose(on: sessionDate) else {
            throw .invalidSessionDate(sessionDate)
        }
        do {
            return try Purchase(
                id: id,
                ticker: ticker,
                shares: shares,
                pricePerShare: limitPrice.amount,
                pricedAt: close,
                priceSource: .limitOrderFill(sessionDate: sessionDate),
            )
        } catch {
            preconditionFailure("A valid buy limit order made an invalid purchase: \(error)")
        }
    }
}
