/// One investment experiment, saved as one `.invsim` document (ADR-0005,
/// where it is called a scenario). It starts with a cash balance and buys
/// investments from it.
public struct Experiment: Sendable, Hashable {
    /// A new experiment with no cash yet.
    public static let empty = Experiment(validCashBalance: .zero, purchases: [])

    /// The cash left after every purchase.
    public let cashBalance: Money
    /// In the order they were made.
    public let purchases: [Purchase]

    public init(cashBalance: Money, purchases: [Purchase] = []) throws(ExperimentError) {
        guard cashBalance.amount >= 0 else {
            throw .negativeCashBalance(cashBalance)
        }
        self.init(validCashBalance: cashBalance, purchases: purchases)
    }

    private init(validCashBalance cashBalance: Money, purchases: [Purchase]) {
        self.cashBalance = cashBalance
        self.purchases = purchases
    }

    /// The experiment after buying `purchase` with its cash. Cash never goes
    /// negative, so a purchase costing more than the balance is rejected.
    public func purchasing(_ purchase: Purchase) throws(ExperimentError) -> Experiment {
        guard purchase.cost <= cashBalance else {
            throw .insufficientCash(cost: purchase.cost, available: cashBalance)
        }
        return Experiment(validCashBalance: cashBalance - purchase.cost, purchases: purchases + [purchase])
    }
}

public enum ExperimentError: Error, Equatable {
    case negativeCashBalance(Money)
    case insufficientCash(cost: Money, available: Money)
}
