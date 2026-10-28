import Foundation

public enum ExperimentError: Error, Equatable {
    case negativeCashBalance(Money)
    case insufficientCash(cost: Money, available: Money)
    case unknownPurchase(UUID)
    case insufficientShares(requested: Int, available: Int)
    case unknownOrder(UUID)
    case orderAlreadyFilled(UUID)
    case orderCancelled(UUID)
    /// The order has filled, expired or been cancelled.
    case orderNotOpen(UUID)
    case invalidSessionDate(String)
    /// A filled buy order without its purchase, or a purchase marked as a
    /// fill without its filled buy order.
    case mismatchedFillPurchase(UUID)
    /// Two purchases or orders share an id. A filled buy order and its
    /// purchase are the one pair that shares one.
    case duplicateID(UUID)
}
