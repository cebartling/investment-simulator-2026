import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct LibraryModelTests {
    private struct Boom: Error, LocalizedError {
        var errorDescription: String? {
            "disk full"
        }
    }

    private func experiment(named name: String?, createdAt: Date? = nil) -> Experiment {
        // swiftlint:disable:next force_try
        try! Experiment(cashBalance: .zero, name: name, createdAt: createdAt)
    }

    private func makeModel(
        _ experiments: [ExperimentID: Experiment] = [:],
    ) -> (LibraryModel, FakeExperimentRepository) {
        let repository = FakeExperimentRepository(experiments)
        return (LibraryModel(repository: repository), repository)
    }

    @Test func `load lists the stored experiments`() async {
        let id = ExperimentID()
        let (model, _) = makeModel([id: experiment(named: "Index funds")])

        await model.load()

        #expect(model.summaries.map(\.id) == [id])
        #expect(model.errorMessage == nil)
    }

    @Test func `a list failure becomes an error message and keeps the old list`() async {
        let id = ExperimentID()
        let (model, repository) = makeModel([id: experiment(named: "Index funds")])
        await model.load()
        repository.failNext(with: Boom())

        await model.load()

        #expect(model.errorMessage == "disk full")
        #expect(model.summaries.map(\.id) == [id])
    }

    @Test func `a later success clears the error message`() async {
        let (model, repository) = makeModel()
        repository.failNext(with: Boom())
        await model.load()

        await model.load()

        #expect(model.errorMessage == nil)
    }

    @Test func `title falls back to Untitled without a name`() {
        let (model, _) = makeModel()

        #expect(model.title(for: ExperimentSummary(id: ExperimentID(), name: nil, createdAt: nil)) == "Untitled")
        #expect(model.title(for: ExperimentSummary(id: ExperimentID(), name: "Tech", createdAt: nil)) == "Tech")
    }

    @Test func `create stores an empty experiment, lists it and selects it`() async {
        let (model, repository) = makeModel()

        await model.create(name: "Tech")

        let created = try? #require(model.summaries.first)
        #expect(created?.name == "Tech")
        #expect(model.selection == created?.id)
        #expect(created.flatMap { repository.stored($0.id) }?.name == "Tech")
    }

    @Test func `create with a blank name stores no name`() async {
        let (model, _) = makeModel()

        await model.create(name: "  ")

        #expect(model.summaries.first?.name == nil)
    }

    @Test func `a create failure selects nothing and shows the error`() async {
        let (model, repository) = makeModel()
        repository.failNext(with: Boom())

        await model.create(name: "Tech")

        #expect(model.selection == nil)
        #expect(model.errorMessage == "disk full")
    }

    @Test func `rename changes the listed name`() async {
        let id = ExperimentID()
        let (model, _) = makeModel([id: experiment(named: "Old")])
        await model.load()

        await model.rename(id, to: "New")

        #expect(model.summaries.first?.name == "New")
    }

    @Test func `rename to blank clears the name`() async {
        let id = ExperimentID()
        let (model, _) = makeModel([id: experiment(named: "Old")])
        await model.load()

        await model.rename(id, to: "   ")

        #expect(model.summaries.first?.name == nil)
    }

    @Test func `renaming a missing experiment says so`() async {
        let (model, _) = makeModel()

        await model.rename(ExperimentID(), to: "New")

        #expect(model.errorMessage == "That experiment no longer exists.")
    }

    @Test func `duplicate lists and selects the copy`() async {
        let id = ExperimentID()
        let (model, _) = makeModel([id: experiment(named: "Original")])
        await model.load()

        await model.duplicate(id)

        #expect(model.summaries.count == 2)
        #expect(model.selection != nil)
        #expect(model.selection != id)
    }

    @Test func `delete waits for confirmation`() async {
        let id = ExperimentID()
        let (model, repository) = makeModel([id: experiment(named: "Old")])
        await model.load()

        model.requestDelete(model.summaries[0])

        #expect(model.pendingDeletion?.id == id)
        #expect(repository.stored(id) != nil)
    }

    @Test func `cancelling a delete keeps the experiment`() async {
        let id = ExperimentID()
        let (model, repository) = makeModel([id: experiment(named: "Old")])
        await model.load()
        model.requestDelete(model.summaries[0])

        model.cancelDelete()
        await model.confirmDelete()

        #expect(model.pendingDeletion == nil)
        #expect(repository.stored(id) != nil)
    }

    @Test func `confirming a delete removes it and clears its selection`() async {
        let id = ExperimentID()
        let (model, repository) = makeModel([id: experiment(named: "Old")])
        await model.load()
        model.selection = id
        model.requestDelete(model.summaries[0])

        await model.confirmDelete()

        #expect(repository.stored(id) == nil)
        #expect(model.summaries.isEmpty)
        #expect(model.selection == nil)
        #expect(model.pendingDeletion == nil)
    }

    @Test func `deleting another experiment keeps the selection`() async {
        let kept = ExperimentID()
        let removed = ExperimentID()
        let (model, _) = makeModel([kept: experiment(named: "A"), removed: experiment(named: "B")])
        await model.load()
        model.selection = kept
        model.requestDelete(model.summaries.first { $0.id == removed }!)

        await model.confirmDelete()

        #expect(model.selection == kept)
    }

    @Test func `a delete failure shows the error and keeps the list`() async {
        let id = ExperimentID()
        let (model, repository) = makeModel([id: experiment(named: "Old")])
        await model.load()
        model.requestDelete(model.summaries[0])
        repository.failNext(with: Boom())

        await model.confirmDelete()

        #expect(model.errorMessage == "disk full")
        #expect(model.summaries.map(\.id) == [id])
        #expect(model.pendingDeletion == nil)
    }
}
