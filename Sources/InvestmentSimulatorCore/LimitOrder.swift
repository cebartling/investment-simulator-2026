import Foundation

/// An order to sell shares of one purchase once the price reaches
/// `limitPrice`. Orders expire; nothing fills them yet.
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

    /// An order with a known expiry, such as one read from a file. New
    /// orders come from `placed(id:purchaseID:shares:limitPrice:at:)`.
    public init(
        id: UUID,
        purchaseID: UUID,
        shares: Int,
        limitPrice: Money,
        placedAt: Date,
        expiresAt: Date,
    ) throws(LimitOrderError) {
        guard shares > 0 else {
            throw .nonPositiveShares(shares)
        }
        guard limitPrice > .zero else {
            throw .nonPositivePrice(limitPrice)
        }
        self.id = id
        self.purchaseID = purchaseID
        self.shares = shares
        self.limitPrice = limitPrice
        self.placedAt = placedAt
        self.expiresAt = expiresAt
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
            expiresAt: marketCalendar.date(byAdding: .day, value: lifetimeInDays, to: placedAt)!,
        )
    }

    private static let marketCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    /// True until the order expires.
    public func isOpen(at date: Date) -> Bool {
        date < expiresAt
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
}
