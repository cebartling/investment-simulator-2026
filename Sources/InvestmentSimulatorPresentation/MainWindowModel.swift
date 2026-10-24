import Foundation
import InvestmentSimulatorCore
import Observation

/// Drives one experiment's window: the sidebar's sections, which one is
/// shown, and the experiment itself.
@Observable
public final class MainWindowModel {
    public let sections = NavigationSection.allCases
    public var selection: NavigationSection? = .experiment

    public private(set) var experiment: Experiment
    public var isShowingNewExperiment: Bool
    public let newExperiment = NewExperimentModel()

    /// Set when the user cancels a new document; the window closes once the
    /// sheet has gone, since a window can't close with a sheet attached.
    public private(set) var shouldCloseWindow = false

    /// `needsSetup` is true for a new, untitled document, which opens the
    /// New Experiment sheet.
    public init(experiment: Experiment, needsSetup: Bool) {
        self.experiment = experiment
        isShowingNewExperiment = needsSetup
    }

    public var cashBalance: Decimal {
        experiment.cashBalance.amount
    }

    /// Does nothing while the input is invalid, leaving the sheet open with
    /// its validation message.
    public func createExperiment() {
        guard let created = newExperiment.create() else {
            return
        }
        experiment = created
        isShowingNewExperiment = false
    }

    public func cancelNewExperiment() {
        isShowingNewExperiment = false
        shouldCloseWindow = true
    }
}
