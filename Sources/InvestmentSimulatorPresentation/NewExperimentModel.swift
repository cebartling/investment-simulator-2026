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

    /// The experiment to create, or nil while the input is invalid; the
    /// reason is in `validationMessage`.
    public func create() -> Experiment? {
        guard canCreate else {
            return nil
        }
        do {
            return try Experiment(cashBalance: Money(cashBalance).roundedToCents())
        } catch {
            preconditionFailure("canCreate allowed an invalid cash balance: \(error)")
        }
    }
}
