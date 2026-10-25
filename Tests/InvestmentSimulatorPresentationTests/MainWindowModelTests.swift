import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct MainWindowModelTests {
    @Test func `sections are experiment, simulation, results in order`() throws {
        let model = try makeModel()

        #expect(model.sections == [.experiment, .simulation, .results])
    }

    @Test func `initial selection is the first section`() throws {
        let model = try makeModel()

        #expect(model.selection == .experiment)
    }

    @Test(arguments: [
        (NavigationSection.experiment, "Experiment"),
        (.simulation, "Simulation"),
        (.results, "Results"),
    ])
    func `section title`(section: NavigationSection, title: String) {
        #expect(section.title == title)
    }

    @Test func `cash balance comes from the experiment`() throws {
        let model = try makeModel(cashBalance: 2500)

        #expect(model.cashBalance == 2500)
    }

    @Test func `new document shows the new experiment sheet`() throws {
        let model = try makeModel(needsSetup: true)

        #expect(model.isShowingNewExperiment)
    }

    @Test func `opened document does not show the new experiment sheet`() throws {
        let model = try makeModel(needsSetup: false)

        #expect(!model.isShowingNewExperiment)
    }

    @Test func `creating the experiment sets its cash balance and hides the sheet`() throws {
        let model = try makeModel(needsSetup: true)
        model.newExperiment.cashBalance = 10000

        let created = model.createExperiment()

        #expect(try created == Experiment(cashBalance: Money(10000)))
        #expect(model.experiment == created)
        #expect(model.cashBalance == 10000)
        #expect(!model.isShowingNewExperiment)
    }

    @Test func `creating a zero balance experiment still returns it`() throws {
        let model = try makeModel(needsSetup: true)

        #expect(model.createExperiment() == Experiment.empty)
    }

    @Test func `invalid create keeps the sheet and the experiment`() throws {
        let model = try makeModel(cashBalance: 0, needsSetup: true)
        model.newExperiment.cashBalance = -1

        #expect(model.createExperiment() == nil)
        #expect(model.isShowingNewExperiment)
        #expect(model.cashBalance == 0)
    }

    @Test func `replacing the experiment shows the document's new balance`() throws {
        let model = try makeModel(cashBalance: 100)

        try model.replaceExperiment(with: Experiment(cashBalance: Money(250)))

        #expect(model.cashBalance == 250)
    }

    @Test func `window stays open by default`() throws {
        let model = try makeModel(needsSetup: true)

        #expect(!model.shouldCloseWindow)
    }

    @Test func `cancelling the new experiment hides the sheet and closes the window`() throws {
        let model = try makeModel(needsSetup: true)

        model.cancelNewExperiment()

        #expect(!model.isShowingNewExperiment)
        #expect(model.shouldCloseWindow)
    }

    @Test func `purchases come from the experiment`() throws {
        let purchase = try Purchase(
            id: fixedPurchaseID,
            ticker: Ticker("VTI"),
            shares: 1,
            pricePerShare: 10,
            pricedAt: Date(timeIntervalSince1970: 0),
            priceSource: .liveQuote(delayed: false),
        )
        let model = try MainWindowModel(
            experiment: Experiment(cashBalance: Money(5), purchases: [purchase]),
            needsSetup: false,
            quotes: FakeQuotes(.failure(.missingAPIKey)),
        )

        #expect(model.purchases == [purchase])
    }

    @Test func `beginning a purchase shows the purchase sheet with the cash balance`() throws {
        let model = try makeModel(cashBalance: 500)

        model.beginPurchase()

        #expect(model.isShowingPurchase)
        #expect(model.purchase?.availableCash == Money(500))
    }

    @Test func `completing a purchase updates the experiment and hides the sheet`() async throws {
        let model = try makeModel(cashBalance: 500, quotes: FakeQuotes(.success(makeQuote(price: "100"))))
        model.beginPurchase()
        let purchase = try #require(model.purchase)
        purchase.tickerText = "VTI"
        purchase.shares = 2
        await purchase.getPrice()

        let updated = try #require(model.completePurchase())

        #expect(updated.cashBalance == Money(300))
        #expect(model.experiment == updated)
        #expect(model.purchases.count == 1)
        #expect(!model.isShowingPurchase)
        #expect(model.purchase == nil)
    }

    @Test func `completing a purchase that can't be bought changes nothing`() throws {
        let model = try makeModel(cashBalance: 500)
        model.beginPurchase()

        #expect(model.completePurchase() == nil)
        #expect(model.isShowingPurchase)
        #expect(model.cashBalance == 500)
    }

    @Test func `cancelling a purchase hides the sheet`() throws {
        let model = try makeModel(cashBalance: 500)
        model.beginPurchase()

        model.cancelPurchase()

        #expect(!model.isShowingPurchase)
        #expect(model.purchase == nil)
    }

    private func makeModel(
        cashBalance: Decimal = 0,
        needsSetup: Bool = false,
        quotes: FakeQuotes = FakeQuotes(.failure(.missingAPIKey)),
    ) throws -> MainWindowModel {
        try MainWindowModel(
            experiment: Experiment(cashBalance: Money(cashBalance)),
            needsSetup: needsSetup,
            quotes: quotes,
        )
    }
}
