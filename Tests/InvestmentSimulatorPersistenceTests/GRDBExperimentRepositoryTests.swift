import Foundation
import GRDB
import InvestmentSimulatorCore
import InvestmentSimulatorPersistence
import Testing

/// The SQLite adapter for `ExperimentRepository` (ADR-0021). Every test uses
/// an in-memory database, so none touches disk.
struct GRDBExperimentRepositoryTests {
    let queue: DatabaseQueue
    let repository: GRDBExperimentRepository

    init() throws {
        queue = try DatabaseQueue()
        repository = try GRDBExperimentRepository(writer: queue)
    }

    // MARK: Round trips

    @Test func `an empty experiment survives a round trip`() async throws {
        let id = ExperimentID()
        let experiment = try Experiment(cashBalance: Money(1000))

        try await repository.save(experiment, as: id)

        #expect(try await repository.load(id) == experiment)
    }

    @Test func `an experiment with every feature survives a round trip`() async throws {
        let id = ExperimentID()
        let experiment = try makeFullExperiment()

        try await repository.save(experiment, as: id)

        #expect(try await repository.load(id) == experiment)
    }

    @Test func `name, notes and created date survive, and nil stays nil`() async throws {
        let named = ExperimentID()
        let bare = ExperimentID()
        let details = try Experiment(
            cashBalance: Money(1),
            name: "Index funds",
            notes: "Line one\nLine two",
            createdAt: Date(timeIntervalSince1970: 1_793_000_000),
        )

        try await repository.save(details, as: named)
        try await repository.save(Experiment(cashBalance: Money(1)), as: bare)

        #expect(try await repository.load(named) == details)
        #expect(try await repository.load(bare).name == nil)
        #expect(try await repository.load(bare).createdAt == nil)
    }

    @Test func `money keeps every digit and is stored as text`() async throws {
        let id = ExperimentID()
        let purchase = try makePurchase(id: 1, shares: 3, price: "123.456789")
        let cash = try Money(#require(Decimal(string: "98765.4321")))
        let experiment = try Experiment(cashBalance: cash, purchases: [purchase])

        try await repository.save(experiment, as: id)

        #expect(try await repository.load(id) == experiment)
        let types = try await queue.read { database in
            try [
                String.fetchOne(database, sql: "SELECT typeof(cash_balance) FROM experiment"),
                String.fetchOne(database, sql: "SELECT typeof(price_per_share) FROM purchase"),
            ]
        }
        #expect(types == ["text", "text"])
    }

    @Test func `a cancelled order keeps its cancelled time and a filled one its session`() async throws {
        let id = ExperimentID()
        let experiment = try makeFullExperiment()

        try await repository.save(experiment, as: id)
        let loaded = try await repository.load(id)

        #expect(loaded.limitOrders.map(\.cancelledAt) == experiment.limitOrders.map(\.cancelledAt))
        #expect(loaded.limitOrders.contains { $0.cancelledAt != nil })
        #expect(loaded.buyLimitOrders.map(\.filledOn) == experiment.buyLimitOrders.map(\.filledOn))
        #expect(loaded.buyLimitOrders.contains { $0.filledOn != nil })
    }

    @Test func `purchases and sales come back in the order they were saved, not by id`() async throws {
        let id = ExperimentID()
        let experiment = try Experiment(
            cashBalance: Money(0),
            purchases: [
                makePurchase(id: 9, shares: 5, price: "10"),
                makePurchase(id: 2, shares: 5, price: "11"),
                makePurchase(id: 5, shares: 5, price: "12"),
            ],
        )

        try await repository.save(experiment, as: id)

        #expect(try await repository.load(id).purchases.map(\.id) == experiment.purchases.map(\.id))
    }

    // MARK: Save

    @Test func `saving again replaces the experiment instead of adding to it`() async throws {
        let id = ExperimentID()
        try await repository.save(makeFullExperiment(), as: id)
        let smaller = try Experiment(cashBalance: Money(5), purchases: [makePurchase(id: 1, shares: 1, price: "1")])

        try await repository.save(smaller, as: id)

        #expect(try await repository.load(id) == smaller)
        #expect(try await repository.list().count == 1)
    }

    @Test func `experiments can reuse the same purchase ids`() async throws {
        let first = ExperimentID()
        let second = ExperimentID()
        let experiment = try Experiment(cashBalance: Money(0), purchases: [makePurchase(id: 1, shares: 1, price: "1")])

        try await repository.save(experiment, as: first)
        try await repository.save(experiment, as: second)

        #expect(try await repository.load(first) == experiment)
        #expect(try await repository.load(second) == experiment)
    }

    // MARK: List

    @Test func `list shows newest first, undated last, ties broken by name`() async throws {
        let old = ExperimentID()
        let new = ExperimentID()
        let undatedB = ExperimentID()
        let undatedA = ExperimentID()
        let oldDate = Date(timeIntervalSince1970: 1000)
        let newDate = Date(timeIntervalSince1970: 2000)
        try await repository.save(Experiment(cashBalance: Money(0), createdAt: oldDate), as: old)
        try await repository.save(Experiment(cashBalance: Money(0), createdAt: newDate), as: new)
        try await repository.save(Experiment(cashBalance: Money(0), name: "B"), as: undatedB)
        try await repository.save(Experiment(cashBalance: Money(0), name: "A"), as: undatedA)

        #expect(try await repository.list().map(\.id) == [new, old, undatedA, undatedB])
    }

    @Test func `list carries the name and created date`() async throws {
        let id = ExperimentID()
        let created = Date(timeIntervalSince1970: 1_793_000_000)
        try await repository.save(Experiment(cashBalance: Money(0), name: "Mine", createdAt: created), as: id)

        #expect(try await repository.list() == [ExperimentSummary(id: id, name: "Mine", createdAt: created)])
    }

    @Test func `list is empty with no experiments`() async throws {
        #expect(try await repository.list().isEmpty)
    }

    // MARK: Rename

    @Test func `rename changes only the name`() async throws {
        let id = ExperimentID()
        let experiment = try makeFullExperiment()
        try await repository.save(experiment, as: id)

        try await repository.rename(id, to: "Renamed")

        let loaded = try await repository.load(id)
        #expect(loaded.name == "Renamed")
        #expect(loaded.editingDetails(name: experiment.name, notes: loaded.notes) == experiment)
    }

    @Test func `rename to nil clears the name`() async throws {
        let id = ExperimentID()
        try await repository.save(Experiment(cashBalance: Money(0), name: "Old"), as: id)

        try await repository.rename(id, to: nil)

        #expect(try await repository.load(id).name == nil)
    }

    // MARK: Duplicate

    @Test func `duplicate stores an equal experiment under a new id`() async throws {
        let id = ExperimentID()
        let experiment = try makeFullExperiment()
        try await repository.save(experiment, as: id)

        let copy = try await repository.duplicate(id)

        #expect(copy != id)
        #expect(try await repository.load(copy) == experiment)
        #expect(try await repository.load(id) == experiment)
        #expect(try await repository.list().count == 2)
    }

    // MARK: Delete

    @Test func `delete removes the experiment and its history`() async throws {
        let id = ExperimentID()
        let other = ExperimentID()
        try await repository.save(makeFullExperiment(), as: id)
        try await repository.save(makeFullExperiment(), as: other)

        try await repository.delete(id)

        #expect(try await repository.list().map(\.id) == [other])
        let counts = try await queue.read { database in
            try ["purchase", "sale", "sell_order", "buy_order"].map { table in
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM \(table) WHERE experiment_id = ?",
                    arguments: [id.rawValue.uuidString],
                )
            }
        }
        #expect(counts == [0, 0, 0, 0])
        #expect(try await repository.load(other) == makeFullExperiment())
    }

    @Test func `an unknown id is not found by load, rename, duplicate or delete`() async throws {
        let id = ExperimentID()
        let notFound = ExperimentRepositoryError.notFound(id)

        await #expect(throws: notFound) { try await repository.load(id) }
        await #expect(throws: notFound) { try await repository.rename(id, to: "x") }
        await #expect(throws: notFound) { try await repository.duplicate(id) }
        await #expect(throws: notFound) { try await repository.delete(id) }
    }
}
