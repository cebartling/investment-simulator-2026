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

    public var isShowingPurchase = false
    /// The Buy sheet's model while it is shown.
    public private(set) var purchase: PurchaseModel?

    private let quotes: any QuoteProviding

    /// Set when the user cancels a new document. The app's `WindowCloser`
    /// then ends the sheet, since a window can't close with one attached,
    /// and closes the window.
    public private(set) var shouldCloseWindow = false

    /// `needsSetup` is true for a new, untitled document, which opens the
    /// New Experiment sheet.
    public init(experiment: Experiment, needsSetup: Bool, quotes: any QuoteProviding) {
        self.experiment = experiment
        isShowingNewExperiment = needsSetup
        self.quotes = quotes
    }

    public var cashBalance: Decimal {
        experiment.cashBalance.amount
    }

    public var purchases: [Purchase] {
        experiment.purchases
    }

    /// Returns the created experiment, for the document to save. Returns nil
    /// while the input is invalid, leaving the sheet open with its
    /// validation message.
    @discardableResult
    public func createExperiment() -> Experiment? {
        guard let created = newExperiment.create() else {
            return nil
        }
        experiment = created
        isShowingNewExperiment = false
        return created
    }

    /// Shows a change the document made itself, such as File › Revert To.
    public func replaceExperiment(with experiment: Experiment) {
        self.experiment = experiment
    }

    public func beginPurchase() {
        purchase = PurchaseModel(availableCash: experiment.cashBalance, quotes: quotes)
        isShowingPurchase = true
    }

    /// Returns the experiment after the purchase, for the document to save.
    /// Returns nil while the purchase can't be bought, leaving the sheet open.
    @discardableResult
    public func completePurchase() -> Experiment? {
        guard let bought = purchase?.buy(), let updated = try? experiment.purchasing(bought) else {
            return nil
        }
        experiment = updated
        cancelPurchase()
        return updated
    }

    public func cancelPurchase() {
        isShowingPurchase = false
        purchase = nil
    }

    public func cancelNewExperiment() {
        isShowingNewExperiment = false
        shouldCloseWindow = true
    }
}
