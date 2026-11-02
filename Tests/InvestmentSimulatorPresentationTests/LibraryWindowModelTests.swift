import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// The library window's destinations and its experiment models (PIN-477,
/// ADR-0021).
@MainActor
struct LibraryWindowModelTests {
    private func experiment(named name: String?, cash: Decimal = 0) -> Experiment {
        // swiftlint:disable:next force_try
        try! Experiment(cashBalance: Money(cash), name: name, createdAt: Date(timeIntervalSince1970: 0))
    }

    private func makeModel(
        _ experiments: [ExperimentID: Experiment] = [:],
    ) -> (LibraryWindowModel, FakeExperimentRepository) {
        let repository = FakeExperimentRepository(experiments)
        let model = LibraryWindowModel(
            library: LibraryModel(repository: repository),
            makeExperimentModel: { id in
                MainWindowModel(
                    id: id,
                    repository: repository,
                    quotes: FakeQuotes(.failure(.missingAPIKey)),
                    dailyPrices: FakeDailyPrices(),
                )
            },
        )
        return (model, repository)
    }

    private func newExperiment(name: String, cash: Decimal) -> NewExperimentModel {
        let input = NewExperimentModel()
        input.name = name
        input.cashBalance = cash
        return input
    }

    @Test func `nothing is selected to begin with`() {
        #expect(makeModel().0.destination == nil)
    }

    @Test func `choosing an experiment selects it in the library`() {
        let id = ExperimentID()
        let (model, _) = makeModel()

        model.destination = .experiment(id)

        #expect(model.library.selection == id)
        #expect(model.destination == .experiment(id))
    }

    @Test func `choosing Research leaves no experiment selected`() {
        let (model, _) = makeModel()
        model.destination = .experiment(ExperimentID())

        model.destination = .research

        #expect(model.library.selection == nil)
        #expect(model.destination == .research)
    }

    @Test func `creating an experiment shows it even while Research is showing`() async {
        let (model, _) = makeModel()
        model.destination = .research

        await model.create(newExperiment(name: "Index funds", cash: 100))

        #expect(model.destination == model.library.selection.map { .experiment($0) })
        #expect(model.library.selection != nil)
    }

    @Test func `duplicating an experiment shows the copy even while Research is showing`() async {
        let id = ExperimentID()
        let (model, _) = makeModel([id: experiment(named: "Index funds")])
        model.destination = .research

        await model.duplicate(id)

        guard case let .experiment(copy)? = model.destination else {
            Issue.record("expected the copy to be showing, got \(String(describing: model.destination))")
            return
        }
        #expect(copy != id)
    }

    @Test func `a failed create leaves Research showing`() async {
        let (model, repository) = makeModel()
        model.destination = .research
        repository.failNext(with: ExperimentRepositoryError.notFound(ExperimentID()))

        await model.create(newExperiment(name: "", cash: 100))

        #expect(model.destination == .research)
    }

    @Test func `an experiment keeps one model, so its sheets survive switching away`() {
        let id = ExperimentID()
        let (model, _) = makeModel()

        #expect(model.experimentModel(for: id) === model.experimentModel(for: id))
        #expect(model.experimentModel(for: id) !== model.experimentModel(for: ExperimentID()))
    }

    @Test func `deleting an experiment drops its model`() async throws {
        let id = ExperimentID()
        let (model, _) = makeModel([id: experiment(named: "Index funds")])
        await model.library.load()
        let before = model.experimentModel(for: id)
        let summary = try #require(model.library.summaries.first)

        model.library.requestDelete(summary)
        await model.confirmDelete()

        #expect(model.experimentModel(for: id) !== before)
    }

    @Test func `loading an experiment reads it once`() async {
        let id = ExperimentID()
        let (model, repository) = makeModel([id: experiment(named: "Index funds", cash: 100)])

        await model.ensureLoaded(id)
        repository.failNext(with: ExperimentRepositoryError.notFound(id))
        await model.ensureLoaded(id)

        let loaded = model.experimentModel(for: id)
        #expect(loaded.experiment.name == "Index funds")
        #expect(loaded.loadError == nil)
    }

    @Test func `a failed load is tried again the next time`() async {
        let id = ExperimentID()
        let (model, repository) = makeModel([id: experiment(named: "Index funds")])
        repository.failNext(with: ExperimentRepositoryError.notFound(id))

        await model.ensureLoaded(id)
        #expect(model.experimentModel(for: id).loadError != nil)
        await model.ensureLoaded(id)

        #expect(model.experimentModel(for: id).loadError == nil)
        #expect(model.experimentModel(for: id).experiment.name == "Index funds")
    }

    @Test func `a purchase from Research shows the experiment with the sheet filled in`() async throws {
        let id = ExperimentID()
        let (model, _) = makeModel([id: experiment(named: "Index funds", cash: 500)])
        model.destination = .research

        try await model.beginPurchase(of: Ticker("VTI"), in: id)

        let experiment = model.experimentModel(for: id)
        #expect(model.destination == .experiment(id))
        #expect(experiment.isShowingPurchase)
        #expect(experiment.purchase?.tickerText == "VTI")
        #expect(experiment.purchase?.availableCash == Money(500))
    }

    @Test func `a buy limit order from Research shows the experiment with the sheet filled in`() async throws {
        let id = ExperimentID()
        let (model, _) = makeModel([id: experiment(named: "Index funds", cash: 500)])

        try await model.beginBuyLimitOrder(of: Ticker("VTI"), in: id)

        let experiment = model.experimentModel(for: id)
        #expect(model.destination == .experiment(id))
        #expect(experiment.isShowingBuyLimitOrder)
        #expect(experiment.buyLimitOrder?.tickerText == "VTI")
        #expect(experiment.buyLimitOrder?.availableCash == Money(500))
    }

    @Test func `creating stores the name and the starting cash, and closes the sheet`() async throws {
        let (model, repository) = makeModel()
        model.beginNewExperiment()
        let input = try #require(model.newExperiment)
        input.name = "  Index funds "
        input.cashBalance = try #require(Decimal(string: "250.005"))

        await model.create(input)

        let id = try #require(model.library.selection)
        #expect(repository.stored(id)?.name == "Index funds")
        #expect(try repository.stored(id)?.cashBalance == Money(#require(Decimal(string: "250.00"))))
        #expect(model.newExperiment == nil)
    }

    @Test func `negative starting cash creates nothing and keeps the sheet open`() async throws {
        let (model, repository) = makeModel()
        model.beginNewExperiment()
        let input = try #require(model.newExperiment)
        input.cashBalance = -1

        await model.create(input)

        #expect(model.library.selection == nil)
        #expect(repository.savedCount == 0)
        #expect(model.newExperiment === input)
    }

    @Test func `a failed create keeps the sheet open`() async throws {
        let (model, repository) = makeModel()
        model.beginNewExperiment()
        let input = try #require(model.newExperiment)
        repository.failNext(with: ExperimentRepositoryError.notFound(ExperimentID()))

        await model.create(input)

        #expect(model.newExperiment === input)
    }

    @Test func `cancelling the new experiment closes the sheet`() {
        let (model, _) = makeModel()
        model.beginNewExperiment()

        model.cancelNewExperiment()

        #expect(model.newExperiment == nil)
    }
}
