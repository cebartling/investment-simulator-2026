import InvestmentSimulatorCore

/// Core doesn't format display strings (ADR-0002), so the presentation
/// layer describes the domain errors a check can raise.
extension ExperimentError {
    nonisolated var message: String {
        switch self {
        case .negativeCashBalance:
            "The experiment's cash balance can't be negative."
        case .insufficientCash:
            "The purchase costs more than the experiment's available cash."
        case .unknownPurchase:
            "A limit order or sale sells shares of a purchase the experiment doesn't have."
        case .insufficientShares:
            "A limit order or sale sells more shares than the purchase has free."
        case .unknownOrder:
            "The experiment has no such limit order."
        case .orderAlreadyFilled:
            "The limit order has already filled."
        case .orderCancelled:
            "The limit order was cancelled."
        case .orderNotOpen:
            "The limit order is no longer open."
        case .mismatchedFillPurchase:
            "A buy limit order's fill doesn't match the experiment's purchases."
        case .duplicateID:
            "Two purchases, orders or sales share an ID."
        case .invalidSessionDate:
            "A limit order's fill date must be written yyyy-MM-dd."
        }
    }
}
