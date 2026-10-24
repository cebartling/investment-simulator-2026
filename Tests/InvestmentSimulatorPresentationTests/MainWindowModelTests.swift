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

        try model.createExperiment()

        #expect(try model.experiment == Experiment(cashBalance: Money(10000)))
        #expect(model.cashBalance == 10000)
        #expect(!model.isShowingNewExperiment)
    }

    @Test func `failed create keeps the sheet and the experiment`() throws {
        let model = try makeModel(cashBalance: 0, needsSetup: true)
        model.newExperiment.cashBalance = -1

        #expect(throws: ExperimentError.self) {
            try model.createExperiment()
        }
        #expect(model.isShowingNewExperiment)
        #expect(model.cashBalance == 0)
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

    private func makeModel(cashBalance: Decimal = 0, needsSetup: Bool = false) throws -> MainWindowModel {
        try MainWindowModel(
            experiment: Experiment(cashBalance: Money(cashBalance)),
            needsSetup: needsSetup,
        )
    }
}
