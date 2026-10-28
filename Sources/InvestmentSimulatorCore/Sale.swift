import Foundation

/// Where a market sale's price came from (ADR-0016). Unlike `PriceSource`,
/// it has no limit fill: a filled sell order stays a `LimitOrder`.
public enum SalePriceSource: Sendable, Hashable {
    /// An intraday quote; `delayed` when the plan's quotes lag the market.
    case liveQuote(delayed: Bool)
    /// The settled close of the session on `sessionDate` (`yyyy-MM-dd`).
    case close(sessionDate: String)

    /// The sale source for a quote's source, or nil for a limit fill, which
    /// quotes never have.
    public init?(_ source: PriceSource) {
        switch source {
        case let .liveQuote(delayed):
            self = .liveQuote(delayed: delayed)
        case let .close(sessionDate):
            self = .close(sessionDate: sessionDate)
        case .limitOrderFill:
            return nil
        }
    }
}

/// A sale of shares of one purchase at a quoted price, right away
/// (ADR-0016).
public struct Sale: Sendable, Hashable, Identifiable {
    public let id: UUID
    /// The purchase whose shares the sale sells.
    public let purchaseID: UUID
    public let shares: Int
    /// As quoted, which can include fractions of a cent.
    public let pricePerShare: Decimal
    public let soldAt: Date
    public let priceSource: SalePriceSource

    public init(
        id: UUID,
        purchaseID: UUID,
        shares: Int,
        pricePerShare: Decimal,
        soldAt: Date,
        priceSource: SalePriceSource,
    ) throws(SaleError) {
        guard shares > 0 else {
            throw .nonPositiveShares(shares)
        }
        guard pricePerShare > 0 else {
            throw .nonPositivePrice(pricePerShare)
        }
        self.id = id
        self.purchaseID = purchaseID
        self.shares = shares
        self.pricePerShare = pricePerShare
        self.soldAt = soldAt
        self.priceSource = priceSource
    }

    /// Price times shares, rounded to cents: what the sale adds to cash.
    public var proceeds: Money {
        Money(pricePerShare).times(shares).roundedToCents()
    }

    /// The proceeds less what the sold shares of `purchase`, the one the
    /// sale sells from, cost.
    public func realizedGain(on purchase: Purchase) -> Money {
        proceeds - purchase.cost(of: shares)
    }
}

public enum SaleError: Error, Equatable {
    case nonPositiveShares(Int)
    case nonPositivePrice(Decimal)
}
