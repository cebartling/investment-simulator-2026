import Foundation
import InvestmentSimulatorCore

/// Market sales and the Sales table (PIN-409).
public extension MainWindowModel {
    func beginSale(of purchase: Purchase) {
        sale = SaleModel(
            purchase: purchase,
            availableShares: experiment.availableShares(of: purchase, at: clock()),
            cashBalance: experiment.cashBalance,
            quotes: quotes,
            clock: clock,
        )
        isShowingSale = true
    }

    /// Returns the experiment after the sale, for the document to save.
    /// Returns nil while the sale can't be made, leaving the sheet open.
    @discardableResult
    func completeSale() -> Experiment? {
        guard let sold = sale?.sell(), let updated = try? experiment.selling(sold) else {
            return nil
        }
        experiment = updated
        celebrationCount += 1
        persist(updated)
        cancelSale()
        return updated
    }

    func cancelSale() {
        isShowingSale = false
        sale = nil
    }
}

/// Edit Details (PIN-408).
public extension MainWindowModel {
    func beginEditingDetails() {
        details = ExperimentDetailsModel(name: experiment.name, notes: experiment.notes)
        isShowingDetails = true
    }

    /// Returns the experiment with the edited name and notes, for the
    /// document to save, and hides the sheet. Returns nil when they didn't
    /// change, so the document isn't marked edited.
    @discardableResult
    func completeEditingDetails() -> Experiment? {
        defer { cancelEditingDetails() }
        guard let details, details.savedName != experiment.name || details.savedNotes != experiment.notes else {
            return nil
        }
        experiment = experiment.editingDetails(name: details.savedName, notes: details.savedNotes)
        persist(experiment)
        return experiment
    }

    func cancelEditingDetails() {
        isShowingDetails = false
        details = nil
    }
}
