import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// A window opened on a stored experiment saves through `ExperimentRepository`
/// (PIN-476, ADR-0021).
extension MainWindowModelTests {
    private struct Boom: Error, LocalizedError {
        var errorDescription: String? {
            "disk full"
        }
    }

    private func seededExperiment(orders: [LimitOrder] = []) throws -> Experiment {
        let purchase = try Purchase(
            id: fixedPurchaseID,
            ticker: Ticker("VTI"),
            shares: 10,
            pricePerShare: 10,
            pricedAt: Date(timeIntervalSince1970: 0),
            priceSource: .liveQuote(delayed: false),
        )
        return try Experiment(cashBalance: Money(100), purchases: [purchase], limitOrders: orders, name: "Index funds")
    }

    private struct StoredModel {
        let model: MainWindowModel
        let repository: FakeExperimentRepository
        let id: ExperimentID
    }

    private func makeStoredModel(
        _ experiment: Experiment?,
        prices: FakeDailyPrices = FakeDailyPrices(),
        clock: @escaping () -> Date = { fixedNow },
    ) -> StoredModel {
        let id = ExperimentID()
        let repository = FakeExperimentRepository(experiment.map { [id: $0] } ?? [:])
        let model = MainWindowModel(
            id: id,
            repository: repository,
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: prices,
            clock: clock,
        )
        return StoredModel(model: model, repository: repository, id: id)
    }

    @Test func `loading shows the stored experiment`() async throws {
        let stored = try seededExperiment()
        let model = makeStoredModel(stored).model

        await model.load()

        #expect(model.experiment == stored)
        #expect(model.loadError == nil)
        #expect(!model.isLoading)
    }

    @Test func `a missing experiment becomes a load error`() async {
        let model = makeStoredModel(nil).model

        await model.load()

        #expect(model.loadError == "That experiment no longer exists.")
        #expect(!model.isLoading)
    }

    @Test func `a repository failure becomes a load error`() async throws {
        let stored = try makeStoredModel(seededExperiment())
        let model = stored.model
        let repository = stored.repository
        repository.failNext(with: Boom())

        await model.load()

        #expect(model.loadError == "disk full")
    }

    @Test func `a window whose load failed does not overwrite the stored experiment`() async throws {
        let stored = try makeStoredModel(seededExperiment(orders: [makeOrder(shares: 4)]))
        let model = stored.model
        let repository = stored.repository
        let id = stored.id
        repository.failNext(with: Boom())
        await model.load()

        _ = model.cancelOrder(id: fixedOrderID)
        model.beginEditingDetails()
        model.details?.name = "Growth"
        model.completeEditingDetails()
        await model.settleSaves()

        #expect(repository.savedCount == 0)
        #expect(repository.stored(id)?.name == "Index funds")
    }

    @Test func `title is the stored name, then Untitled`() async throws {
        let named = try makeStoredModel(seededExperiment()).model
        await named.load()
        let unnamed = try makeStoredModel(Experiment(cashBalance: .zero)).model
        await unnamed.load()

        #expect(named.title == "Index funds")
        #expect(unnamed.title == "Untitled")
    }

    @Test func `saving details stores the experiment`() async throws {
        let stored = try makeStoredModel(seededExperiment())
        let model = stored.model
        let repository = stored.repository
        let id = stored.id
        await model.load()
        model.beginEditingDetails()
        model.details?.name = "Growth"

        let updated = try #require(model.completeEditingDetails())
        await model.settleSaves()

        #expect(repository.stored(id) == updated)
        #expect(model.saveError == nil)
    }

    @Test func `cancelling an order stores the experiment`() async throws {
        let stored = try makeStoredModel(seededExperiment(orders: [makeOrder(shares: 4)]))
        let model = stored.model
        let repository = stored.repository
        let id = stored.id
        await model.load()

        let updated = try #require(model.cancelOrder(id: fixedOrderID))
        await model.settleSaves()

        #expect(repository.stored(id) == updated)
    }

    @Test func `checking orders stores the fills`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-28", high: 13)]])
        let stored = try makeStoredModel(
            seededExperiment(orders: [makeOrder(shares: 4)]),
            prices: prices,
            clock: { threeDaysLater },
        )
        let model = stored.model
        let repository = stored.repository
        let id = stored.id
        await model.load()

        let updated = try #require(await model.checkLimitOrders())
        await model.settleSaves()

        #expect(repository.stored(id) == updated)
    }

    @Test func `a change that finds nothing is not stored`() async throws {
        let stored = try makeStoredModel(seededExperiment())
        let model = stored.model
        let repository = stored.repository
        await model.load()
        model.beginEditingDetails()

        #expect(model.completeEditingDetails() == nil)
        await model.settleSaves()

        #expect(repository.savedCount == 0)
    }

    @Test func `a save failure shows an error and keeps the change`() async throws {
        let stored = try makeStoredModel(seededExperiment())
        let model = stored.model
        let repository = stored.repository
        let id = stored.id
        await model.load()
        model.beginEditingDetails()
        model.details?.name = "Growth"
        repository.failNext(with: Boom())

        let updated = try #require(model.completeEditingDetails())
        await model.settleSaves()

        #expect(model.saveError == "disk full")
        #expect(model.experiment == updated)
        #expect(repository.stored(id)?.name == "Index funds")
    }

    @Test func `the next successful save clears the save error`() async throws {
        let stored = try makeStoredModel(seededExperiment())
        let model = stored.model
        let repository = stored.repository
        await model.load()
        repository.failNext(with: Boom())
        model.beginEditingDetails()
        model.details?.name = "Growth"
        model.completeEditingDetails()
        await model.settleSaves()

        model.beginEditingDetails()
        model.details?.name = "Value"
        model.completeEditingDetails()
        await model.settleSaves()

        #expect(model.saveError == nil)
    }

    @Test func `saves reach the repository in the order the changes were made`() async throws {
        let stored = try makeStoredModel(seededExperiment())
        let model = stored.model
        let repository = stored.repository
        let id = stored.id
        await model.load()
        for name in ["One", "Two", "Three"] {
            model.beginEditingDetails()
            model.details?.name = name
            model.completeEditingDetails()
        }
        await model.settleSaves()

        #expect(repository.stored(id)?.name == "Three")
    }

    @Test func `a window without a repository has nothing to settle`() async throws {
        let model = try await makeModel()

        await model.settleSaves()

        #expect(model.saveError == nil)
    }
}
