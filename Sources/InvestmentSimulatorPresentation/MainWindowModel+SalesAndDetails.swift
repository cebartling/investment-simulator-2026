import Foundation
import InvestmentSimulatorCore

/// Market sales and the Sales table (PIN-409).
public extension MainWindowModel {
    /// Shows Market Sell for the purchases of `ticker` still held, starting
    /// on `purchaseID` if given. Does nothing with none held.
    func beginSale(of ticker: Ticker, selecting purchaseID: UUID? = nil) {
        let choices = sellablePurchases(of: ticker)
        guard !choices.isEmpty else {
            return
        }
        sale = SaleModel(
            choices: choices,
            selecting: purchaseID,
            cashBalance: experiment.cashBalance,
            quotes: quotes,
            clock: clock,
        )
        isShowingSale = true
    }

    /// The purchases of `ticker` with shares still held, in the order they
    /// were made, each with its shares free now.
    internal func sellablePurchases(of ticker: Ticker) -> [SellablePurchase] {
        let now = clock()
        return experiment.purchases
            .filter { $0.ticker == ticker && experiment.heldShares(of: $0) > 0 }
            .map { SellablePurchase(purchase: $0, availableShares: experiment.availableShares(of: $0, at: now)) }
    }

    /// Returns the experiment after the sale.
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

    /// Returns the experiment with the edited name and notes and hides the
    /// sheet. Returns nil when they didn't change, so nothing is saved.
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

    /// Takes a name changed in the library, without saving it again.
    internal func applyName(_ name: String?) {
        experiment = experiment.editingDetails(name: name, notes: experiment.notes)
    }

    func cancelEditingDetails() {
        isShowingDetails = false
        details = nil
    }
}
