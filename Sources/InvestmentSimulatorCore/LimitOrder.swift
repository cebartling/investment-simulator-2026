import Foundation

/// An order to sell shares of one purchase once the price reaches
/// `limitPrice`. It fills at exactly that price, or expires.
public struct LimitOrder: Sendable, Hashable, Identifiable {
    /// Calendar days from placing an order to its expiry.
    public static let lifetimeInDays = 90

    public let id: UUID
    /// The purchase whose shares the order sells.
    public let purchaseID: UUID
    public let shares: Int
    /// In whole cents.
    public let limitPrice: Money
    public let placedAt: Date
    public let expiresAt: Date
    /// The session (`yyyy-MM-dd`) the order filled in, or nil while unfilled.
    public let filledOn: String?

    /// An order with a known expiry and fill, such as one read from a file.
    /// New orders come from `placed(id:purchaseID:shares:limitPrice:at:)`.
    public init(
        id: UUID,
        purchaseID: UUID,
        shares: Int,
        limitPrice: Money,
        placedAt: Date,
        expiresAt: Date,
        filledOn: String? = nil,
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
        self.id = id
        self.purchaseID = purchaseID
        self.shares = shares
        self.limitPrice = limitPrice
        self.placedAt = placedAt
        self.expiresAt = expiresAt
        self.filledOn = filledOn
    }

    /// A new order placed at `placedAt`, expiring `lifetimeInDays` calendar
    /// days later at the same time of day in New York, the market's time zone.
    public static func placed(
        id: UUID,
        purchaseID: UUID,
        shares: Int,
        limitPrice: Money,
        at placedAt: Date,
    ) throws(LimitOrderError) -> LimitOrder {
        try LimitOrder(
            id: id,
            purchaseID: purchaseID,
            shares: shares,
            limitPrice: limitPrice,
            placedAt: placedAt,
            expiresAt: expiry(forPlacedAt: placedAt),
        )
    }

    /// When an order placed at `placedAt` expires.
    public static func expiry(forPlacedAt placedAt: Date) -> Date {
        marketCalendar.date(byAdding: .day, value: lifetimeInDays, to: placedAt)!
    }

    /// True until the order fills or expires.
    public func isOpen(at date: Date) -> Bool {
        filledOn == nil && date < expiresAt
    }

    /// The order filled at its limit price in the session on `sessionDate`.
    public func filled(on sessionDate: String) throws(LimitOrderError) -> LimitOrder {
        try LimitOrder(
            id: id,
            purchaseID: purchaseID,
            shares: shares,
            limitPrice: limitPrice,
            placedAt: placedAt,
            expiresAt: expiresAt,
            filledOn: sessionDate,
        )
    }

    /// What a fill adds to cash: the limit price times the shares.
    public var proceeds: Money {
        limitPrice.times(shares).roundedToCents()
    }

    /// The price that makes `percent` profit on each share of `purchase`,
    /// rounded up to cents so the profit never falls short.
    public static func limitPrice(
        forProfitPercent percent: Decimal,
        on purchase: Purchase,
    ) throws(LimitOrderError) -> Money {
        guard percent >= 0 else {
            throw .negativeProfitPercent(percent)
        }
        return Money(purchase.pricePerShare * (1 + percent / 100)).roundedUpToCents()
    }
}

public enum LimitOrderError: Error, Equatable {
    case nonPositiveShares(Int)
    case nonPositivePrice(Money)
    case negativeProfitPercent(Decimal)
    case invalidSessionDate(String)
}
