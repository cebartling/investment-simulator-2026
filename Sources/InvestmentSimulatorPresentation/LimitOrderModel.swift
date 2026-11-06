import Foundation
import InvestmentSimulatorCore
import Observation

/// Drives the Sell Limit sheet: a limit order on one of a ticker's
/// purchases, which the user chooses (PIN-510), priced by a typed limit
/// price or a percent profit.
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

    /// The purchases of one ticker the order can sell from.
    public let choices: [SellablePurchase]
    /// The purchase the order sells from. Choosing another sells all its
    /// free shares, and a typed price starts again at its price.
    public var selectedPurchaseID: UUID {
        didSet {
            shares = availableShares
            enteredPrice = Self.startingPrice(of: purchase)
        }
    }

    private let clock: () -> Date
    private let orderID: UUID

    /// Starts on `purchaseID` when it is one of `choices`, which must not be
    /// empty, else on the first with free shares. `clock` tells the time;
    /// the order is placed when `place()` is called. `orderID` identifies it.
    public init(
        choices: [SellablePurchase],
        selecting purchaseID: UUID? = nil,
        clock: @escaping () -> Date = Date.init,
        orderID: UUID = UUID(),
    ) {
        let initial = choices.choice(withID: choices.initialID(preferring: purchaseID))
        self.choices = choices
        selectedPurchaseID = initial.id
        self.clock = clock
        self.orderID = orderID
        enteredPrice = Self.startingPrice(of: initial.purchase)
        shares = initial.availableShares
    }

    public var purchase: Purchase {
        choices.choice(withID: selectedPurchaseID).purchase
    }

    /// Shares of the purchase not already in an open order.
    public var availableShares: Int {
        choices.choice(withID: selectedPurchaseID).availableShares
    }

    /// The purchase price in cents, where a typed price starts.
    private static func startingPrice(of purchase: Purchase) -> Decimal {
        Money(purchase.pricePerShare).roundedToCents().amount
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
