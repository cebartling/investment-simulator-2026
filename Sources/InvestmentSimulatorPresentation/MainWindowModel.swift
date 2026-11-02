import Foundation
import InvestmentSimulatorCore
import Observation

/// Drives one experiment's window: the sidebar's sections, which one is
/// shown, and the experiment itself.
@Observable
public final class MainWindowModel {
    public let sections = NavigationSection.allCases
    public var selection: NavigationSection? = .experiment

    public internal(set) var experiment: Experiment
    public var isShowingNewExperiment: Bool
    public let newExperiment: NewExperimentModel
    /// Prices the held shares for the header (PIN-408).
    public let holdingsPrices: HoldingsPricesModel

    public var isShowingPurchase = false
    /// The Buy sheet's model while it is shown.
    public private(set) var purchase: PurchaseModel?

    public var isShowingLimitOrder = false
    /// The Sell Limit sheet's model while it is shown.
    public private(set) var limitOrder: LimitOrderModel?

    public var isShowingSale = false
    /// The Market Sell sheet's model while it is shown.
    public internal(set) var sale: SaleModel?

    public var isShowingBuyLimitOrder = false
    /// The Buy Limit sheet's model while it is shown.
    public private(set) var buyLimitOrder: BuyLimitOrderModel?

    public var isShowingDetails = false
    /// The Edit Details sheet's model while it is shown.
    public internal(set) var details: ExperimentDetailsModel?

    /// Whether the order rows include expired and cancelled orders. Off in
    /// each new window, and never saved.
    public var showsExpiredAndCancelledOrders = false

    /// True while Check Orders fetches prices.
    public private(set) var isCheckingOrders = false
    /// What the last Check Orders found, or why it failed.
    public private(set) var orderCheckMessage: String?

    /// Counts the buys, the sales and the checks that filled orders, buy or
    /// sell, so the window can celebrate each one.
    public internal(set) var celebrationCount = 0

    let quotes: any QuoteProviding
    private let dailyPrices: any DailyPriceProviding
    let clock: () -> Date

    /// Where a window opened from the library saves (ADR-0021). Nil for a
    /// document window, which hands each change back to its document.
    private let storage: ExperimentStorage?

    /// True from the start of a repository-backed window until `load()`
    /// finishes.
    public private(set) var isLoading = false
    /// Why `load()` failed, or nil.
    public private(set) var loadError: String?
    /// Why the last save failed, or nil after one that worked. The change
    /// stays in the window, so the next change saves it again.
    public var saveError: String? {
        storage?.saveError
    }

    /// Set when the user cancels a new document. The app's `WindowCloser`
    /// then ends the sheet, since a window can't close with one attached,
    /// and closes the window.
    public private(set) var shouldCloseWindow = false

    /// Counts the times Research started a sheet here, so the app's
    /// `WindowRaiser` can bring this window forward (ADR-0020).
    public internal(set) var raiseCount = 0

    /// `needsSetup` is true for a new, untitled document, which opens the
    /// New Experiment sheet. `clock` tells the time experiments are created
    /// and orders are placed and checked.
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
        newExperiment = NewExperimentModel(clock: clock)
        holdingsPrices = HoldingsPricesModel(quotes: quotes)
        storage = nil
    }

    /// A window on the stored experiment `id`. Call `load()` to read it; each
    /// later change is saved through `repository`. The library makes the
    /// experiment, so there's no New Experiment sheet.
    public init(
        id: ExperimentID,
        repository: any ExperimentRepository,
        quotes: any QuoteProviding,
        dailyPrices: any DailyPriceProviding,
        clock: @escaping () -> Date = Date.init,
    ) {
        experiment = .empty
        isShowingNewExperiment = false
        self.quotes = quotes
        self.dailyPrices = dailyPrices
        self.clock = clock
        newExperiment = NewExperimentModel(clock: clock)
        holdingsPrices = HoldingsPricesModel(quotes: quotes)
        storage = ExperimentStorage(id: id, repository: repository)
        isLoading = true
    }

    public func load() async {
        guard let storage else {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            experiment = try await storage.repository.load(storage.id)
            loadError = nil
        } catch let error as ExperimentRepositoryError {
            loadError = LibraryModel.message(for: error)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Waits for every save started so far. For tests, and for a window that
    /// is closing.
    public func settleSaves() async {
        await storage?.settle()
    }

    /// Saves nothing until `load()` has read the stored experiment: until
    /// then, and after a failed load, `experiment` is a placeholder that
    /// would replace the stored one. `loadError` tells the user why.
    func persist(_ updated: Experiment) {
        guard !isLoading, loadError == nil else {
            return
        }
        storage?.save(updated)
    }

    public var cashBalance: Decimal {
        experiment.cashBalance.amount
    }

    public var purchases: [Purchase] {
        experiment.purchases
    }

    /// The cash held by buy orders open at `date`. Takes the date, so a view
    /// can redraw it as orders expire.
    public func reservedCash(at date: Date) -> Decimal {
        experiment.reservedCash(at: readingDate(date)).amount
    }

    /// The later of `date` and now. A minute timeline passes the start of
    /// the minute, which is before an order cancelled during it.
    func readingDate(_ date: Date) -> Date {
        max(date, clock())
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
        persist(created)
        return created
    }

    /// Shows a change the document made itself, such as File › Revert To.
    public func replaceExperiment(with experiment: Experiment) {
        self.experiment = experiment
    }

    public func beginPurchase() {
        purchase = PurchaseModel(availableCash: experiment.availableCash(at: clock()), quotes: quotes)
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
        persist(updated)
        cancelPurchase()
        return updated
    }

    public func cancelPurchase() {
        isShowingPurchase = false
        purchase = nil
    }

    /// True when a settled session could fill an order open at `date`, and
    /// no check is running. Takes the date, so a view can redraw it as days
    /// pass.
    public func canCheckOrders(at date: Date) -> Bool {
        !isCheckingOrders && !experiment.sessionsToReplay(at: readingDate(date)).isEmpty
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
        let filledCount = Self.filledCount(of: updated) - Self.filledCount(of: checked)
        guard filledCount > 0 else {
            orderCheckMessage = "No orders filled."
            return nil
        }
        experiment = updated
        celebrationCount += 1
        persist(updated)
        orderCheckMessage = filledCount == 1 ? "1 order filled." : "\(filledCount) orders filled."
        return updated
    }

    private static func filledCount(of experiment: Experiment) -> Int {
        experiment.limitOrders.count { $0.filledOn != nil } + experiment.buyLimitOrders.count { $0.filledOn != nil }
    }

    /// Returns the experiment with the order `id`, buy or sell, cancelled
    /// now, for the document to save. Returns nil when no such order is
    /// open.
    @discardableResult
    public func cancelOrder(id: UUID) -> Experiment? {
        guard let updated = try? experiment.cancelling(orderID: id, at: clock()) else {
            return nil
        }
        experiment = updated
        persist(updated)
        return updated
    }

    public func beginBuyLimitOrder() {
        buyLimitOrder = BuyLimitOrderModel(
            availableCash: experiment.availableCash(at: clock()),
            quotes: quotes,
            clock: clock,
        )
        isShowingBuyLimitOrder = true
    }

    /// Returns the experiment with the buy order placed, for the document to
    /// save. Returns nil while the order can't be placed, leaving the sheet
    /// open.
    @discardableResult
    public func completeBuyLimitOrder() -> Experiment? {
        guard let order = buyLimitOrder?.place(), let updated = try? experiment.placing(order) else {
            return nil
        }
        experiment = updated
        persist(updated)
        cancelBuyLimitOrder()
        return updated
    }

    public func cancelBuyLimitOrder() {
        isShowingBuyLimitOrder = false
        buyLimitOrder = nil
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
        persist(updated)
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

/// The Experiment header (PIN-408).
public extension MainWindowModel {
    /// The stored name, else "Untitled" (ADR-0015, ADR-0021).
    var title: String {
        experiment.name ?? LibraryModel.untitled
    }

    /// The experiment's name, else its file's name, else "Untitled" for a
    /// document never saved. Takes the file's URL, which Save As changes.
    func title(fileURL: URL?) -> String {
        experiment.name ?? fileURL?.deletingPathExtension().lastPathComponent ?? LibraryModel.untitled
    }

    /// The document's file name for the window footer (PIN-411), or "Not
    /// saved" before its first save. Takes the file's URL, which Save As
    /// changes.
    func fileLabel(fileURL: URL?) -> String {
        fileURL?.lastPathComponent ?? "Not saved"
    }

    /// The cash a purchase or new buy order can spend at `date`. Takes the
    /// date, so a view can redraw it as orders expire.
    func availableCash(at date: Date) -> Decimal {
        experiment.availableCash(at: readingDate(date)).amount
    }
}
