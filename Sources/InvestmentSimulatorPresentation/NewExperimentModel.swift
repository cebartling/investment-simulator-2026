import Foundation
import InvestmentSimulatorCore
import Observation

/// Drives the New Experiment sheet: the starting cash balance being entered.
@Observable
public final class NewExperimentModel {
    public var cashBalance: Decimal = 0

    public init() {}

    public var canCreate: Bool {
        cashBalance >= 0
    }

    public var validationMessage: String? {
        canCreate ? nil : "Cash balance can't be negative."
    }

    public func create() throws -> Experiment {
        try Experiment(cashBalance: Money(cashBalance).roundedToCents())
    }
}
