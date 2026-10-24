/// One investment experiment, saved as one `.invsim` document (ADR-0005,
/// where it is called a scenario). It starts with a cash balance.
public struct Experiment: Sendable, Hashable {
    public let cashBalance: Money

    public init(cashBalance: Money) throws(ExperimentError) {
        guard cashBalance.amount >= 0 else {
            throw .negativeCashBalance(cashBalance)
        }
        self.cashBalance = cashBalance
    }
}

public enum ExperimentError: Error, Equatable {
    case negativeCashBalance(Money)
}
