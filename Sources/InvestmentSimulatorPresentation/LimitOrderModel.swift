import Foundation
import InvestmentSimulatorCore
import Observation

/// Drives the Sell Limit sheet: a limit order on one purchase, priced by a
/// typed limit price or a percent profit.
@Observable
public final class LimitOrderModel {
    public enum PriceMode: Hashable, CaseIterable {
        case profitPercent
        case limitPrice
    }

    public var mode = PriceMode.profitPercent
    public var profitPercent: Decimal = 0
    /// Typed in `.limitPrice` mode; starts at the purchase price.
    public var enteredPrice: Decimal
    public var shares: Int

    public let purchase: Purchase
    /// Shares of the purchase not already in an open order.
    public let availableShares: Int

    private let clock: () -> Date
    private let orderID: UUID

    /// `clock` tells the time; the order is placed when `place()` is
    /// called. `orderID` identifies it.
    public init(
        purchase: Purchase,
        availableShares: Int,
        clock: @escaping () -> Date = Date.init,
        orderID: UUID = UUID(),
    ) {
        self.purchase = purchase
        self.availableShares = availableShares
        self.clock = clock
        self.orderID = orderID
        enteredPrice = Money(purchase.pricePerShare).roundedToCents().amount
        shares = availableShares
    }

    /// When the order would expire if it were placed now.
    public var expiresAt: Date {
        LimitOrder.expiry(forPlacedAt: clock())
    }

    /// The order's price in whole cents, or nil while the input is invalid.
    /// A typed price is normalized with banker's rounding (ADR-0002); a
    /// percent profit rounds up, so the profit never falls short.
    public var limitPrice: Money? {
        switch mode {
        case .profitPercent:
            return try? LimitOrder.limitPrice(forProfitPercent: profitPercent, on: purchase)
        case .limitPrice:
            let rounded = Money(enteredPrice).roundedToCents()
            return rounded > .zero ? rounded : nil
        }
    }

    /// What selling the shares at the limit price makes over the purchase
    /// price, rounded to cents. Nil while the order can't be placed.
    public var profit: Money? {
        guard sharesMessage == nil else {
            return nil
        }
        return limitPrice.map { Money($0.amount - purchase.pricePerShare).times(shares).roundedToCents() }
    }

    public var priceMessage: String? {
        guard limitPrice == nil else {
            return nil
        }
        return switch mode {
        case .profitPercent: "Profit can't be negative."
        case .limitPrice: "Enter a limit price above zero."
        }
    }

    public var sharesMessage: String? {
        if availableShares <= 0 {
            return "Every share of this purchase is in an open order."
        }
        return (1 ... availableShares).contains(shares) ? nil : "Sell between 1 and \(availableShares) shares."
    }

    public var canPlace: Bool {
        limitPrice != nil && sharesMessage == nil
    }

    /// The order to place, or nil while the input is invalid.
    public func place() -> LimitOrder? {
        guard canPlace, let limitPrice else {
            return nil
        }
        do {
            return try LimitOrder.placed(
                id: orderID,
                purchaseID: purchase.id,
                shares: shares,
                limitPrice: limitPrice,
                at: clock(),
            )
        } catch {
            preconditionFailure("canPlace allowed an invalid limit order: \(error)")
        }
    }
}
