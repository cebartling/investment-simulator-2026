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

    public var isShowingLimitOrder = false
    /// The Sell Limit sheet's model while it is shown.
    public private(set) var limitOrder: LimitOrderModel?

    /// True while Check Orders fetches prices.
    public private(set) var isCheckingOrders = false
    /// What the last Check Orders found, or why it failed.
    public private(set) var orderCheckMessage: String?

    /// Counts the buys and the checks that filled orders, so the window can
    /// celebrate each one.
    public private(set) var celebrationCount = 0

    private let quotes: any QuoteProviding
    private let dailyPrices: any DailyPriceProviding
    private let clock: () -> Date

    /// Set when the user cancels a new document. The app's `WindowCloser`
    /// then ends the sheet, since a window can't close with one attached,
    /// and closes the window.
    public private(set) var shouldCloseWindow = false

    /// `needsSetup` is true for a new, untitled document, which opens the
    /// New Experiment sheet. `clock` tells the time orders are placed and
    /// checked.
    public init(
        experiment: Experiment,
        needsSetup: Bool,
        quotes: any QuoteProviding,
        dailyPrices: any DailyPriceProviding,
        clock: @escaping () -> Date = Date.init,
    ) {
        self.experiment = experiment
        isShowingNewExperiment = needsSetup
        self.quotes = quotes
        self.dailyPrices = dailyPrices
        self.clock = clock
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
        guard let bought = purchase?.buy(), let updated = try? experiment.purchasing(bought, at: clock()) else {
            return nil
        }
        experiment = updated
        celebrationCount += 1
        cancelPurchase()
        return updated
    }

    public func cancelPurchase() {
        isShowingPurchase = false
        purchase = nil
    }

    /// The limit orders as they stand at `date`, so a view can redraw them
    /// as orders expire.
    public func limitOrderRows(at date: Date) -> [LimitOrderRow] {
        let tickers = Dictionary(uniqueKeysWithValues: experiment.purchases.map { ($0.id, $0.ticker) })
        return experiment.limitOrders.compactMap { order in
            // Experiment rejects an order whose purchase it doesn't have.
            tickers[order.purchaseID].map {
                LimitOrderRow(order: order, ticker: $0, status: status(of: order, at: date))
            }
        }
    }

    private func status(of order: LimitOrder, at date: Date) -> LimitOrderRow.Status {
        if let filledOn = order.filledOn {
            .filled(sessionDate: filledOn)
        } else if order.isOpen(at: date) {
            .open
        } else {
            .expired
        }
    }

    /// True when a settled session could fill an order open at `date`, and
    /// no check is running. Takes the date, so a view can redraw it as days
    /// pass.
    public func canCheckOrders(at date: Date) -> Bool {
        !isCheckingOrders && !experiment.sessionsToReplay(at: date).isEmpty
    }

    /// Fetches each ticker's daily bars and fills the orders they reach
    /// (ADR-0013). Returns the experiment after the fills, for the document
    /// to save, or nil when nothing filled or the check failed;
    /// `orderCheckMessage` says which.
    @discardableResult
    public func checkLimitOrders() async -> Experiment? {
        guard !isCheckingOrders else {
            return nil
        }
        let now = clock()
        let checked = experiment
        isCheckingOrders = true
        orderCheckMessage = nil
        defer { isCheckingOrders = false }

        var bars: [Ticker: [DailyBar]] = [:]
        do throws(QuoteError) {
            for (ticker, sessions) in checked.sessionsToReplay(at: now) {
                bars[ticker] = try await dailyPrices.dailyBars(
                    for: ticker,
                    from: sessions.lowerBound,
                    through: sessions.upperBound,
                )
            }
        } catch {
            orderCheckMessage = error.localizedDescription
            return nil
        }

        // The bars cover the orders of the experiment checked. If it changed
        // while they loaded, as after File › Revert To, they may not cover
        // the orders shown now.
        guard experiment == checked else {
            orderCheckMessage = "The experiment changed during the check. Check again."
            return nil
        }
        let updated: Experiment
        do {
            updated = try checked.fillingLimitOrders(from: bars, at: now)
        } catch {
            orderCheckMessage = "Couldn't fill the orders: \(error.localizedDescription)"
            return nil
        }
        let filledCount = updated.limitOrders.count { $0.filledOn != nil }
            - checked.limitOrders.count { $0.filledOn != nil }
        guard filledCount > 0 else {
            orderCheckMessage = "No orders filled."
            return nil
        }
        experiment = updated
        celebrationCount += 1
        orderCheckMessage = filledCount == 1 ? "1 order filled." : "\(filledCount) orders filled."
        return updated
    }

    public func beginLimitOrder(for purchase: Purchase) {
        limitOrder = LimitOrderModel(
            purchase: purchase,
            availableShares: experiment.availableShares(of: purchase, at: clock()),
            clock: clock,
        )
        isShowingLimitOrder = true
    }

    /// Returns the experiment with the order placed, for the document to
    /// save. Returns nil while the order can't be placed, leaving the sheet
    /// open.
    @discardableResult
    public func completeLimitOrder() -> Experiment? {
        guard let order = limitOrder?.place(), let updated = try? experiment.placing(order) else {
            return nil
        }
        experiment = updated
        cancelLimitOrder()
        return updated
    }

    public func cancelLimitOrder() {
        isShowingLimitOrder = false
        limitOrder = nil
    }

    public func cancelNewExperiment() {
        isShowingNewExperiment = false
        shouldCloseWindow = true
    }
}
