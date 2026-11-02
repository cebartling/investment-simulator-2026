import Foundation
import GRDB
import InvestmentSimulatorCore
import InvestmentSimulatorPersistence
import Testing

/// Stored data that can't be read back, and databases that can't be opened.
extension GRDBExperimentRepositoryTests {
    @Test(arguments: [
        ("UPDATE purchase SET shares = 0", "nonPositiveShares(0)"),
        ("UPDATE sell_order SET cancelled_at = placed_at", "filledAndCancelled"),
        ("UPDATE sell_order SET purchase_id = '00000000-0000-0000-0000-0000000000EE'", "unknownPurchase"),
        ("UPDATE sale SET shares = 99", "insufficientShares"),
        ("UPDATE sale SET id = '00000000-0000-0000-0000-000000000001' WHERE position = 0", "duplicateID"),
    ])
    func `a stored history that doesn't make a valid experiment is corrupt`(
        corruption: String,
        expectedDetail: String,
    ) async throws {
        let id = ExperimentID()
        try await repository.save(makeFullExperiment(), as: id)
        try await queue.write { database in
            try database.execute(sql: corruption)
        }

        let error = try await #require(throws: ExperimentRepositoryError.self) {
            try await repository.load(id)
        }

        guard case let .corrupt(corruptID, detail) = error else {
            Issue.record("Expected corrupt, got \(error)")
            return
        }
        #expect(corruptID == id)
        #expect(detail.contains(expectedDetail), "detail was \(detail)")
    }

    @Test func `a stored value of the wrong type is corrupt, not a crash`() async throws {
        let id = ExperimentID()
        try await repository.save(
            Experiment(cashBalance: Money(1), purchases: [makePurchase(id: 1, shares: 1, price: "1")]),
            as: id,
        )
        try await queue.write { database in
            try database.execute(sql: "UPDATE purchase SET shares = 'many'")
        }

        let error = try await #require(throws: ExperimentRepositoryError.self) {
            try await repository.load(id)
        }

        #expect(error == .corrupt(id, detail: "purchase shares isn't a whole number"))
    }

    @Test func `dates keep their sub-millisecond precision`() async throws {
        let id = ExperimentID()
        let moment = Date(timeIntervalSince1970: 1_793_100_000.123_456)
        let purchase = try Purchase(
            id: uuid(1),
            ticker: Ticker("VTI"),
            shares: 1,
            pricePerShare: 1,
            pricedAt: moment,
            priceSource: .liveQuote(delayed: false),
        )
        let experiment = try Experiment(cashBalance: Money(1), purchases: [purchase], createdAt: moment)

        try await repository.save(experiment, as: id)

        #expect(try await repository.load(id) == experiment)
    }

    @Test func `an unreadable created date doesn't hide the library, and the experiment can be deleted`() async throws {
        let good = ExperimentID()
        let damaged = ExperimentID()
        try await repository.save(Experiment(cashBalance: Money(0), name: "Good"), as: good)
        try await repository.save(Experiment(cashBalance: Money(0), name: "Damaged"), as: damaged)
        try await queue.write { database in
            try database.execute(
                sql: "UPDATE experiment SET created_at = 'yesterday' WHERE id = ?",
                arguments: [damaged.rawValue.uuidString],
            )
        }

        let listed = try await repository.list()

        #expect(Set(listed.map(\.id)) == [good, damaged])
        #expect(listed.first { $0.id == damaged }?.createdAt == nil)
        await #expect(throws: ExperimentRepositoryError.corrupt(damaged, detail: "created date isn't a valid date")) {
            try await repository.load(damaged)
        }
        try await repository.delete(damaged)
        #expect(try await repository.list().map(\.id) == [good])
    }

    @Test func `a row whose id isn't an id is left out of the list`() async throws {
        let good = ExperimentID()
        try await repository.save(Experiment(cashBalance: Money(0)), as: good)
        try await repository.save(Experiment(cashBalance: Money(0)), as: ExperimentID())
        try await queue.write { database in
            try database.execute(
                sql: "UPDATE experiment SET id = 'not an id' WHERE id <> ?",
                arguments: [good.rawValue.uuidString],
            )
        }

        #expect(try await repository.list().map(\.id) == [good])
    }

    @Test func `a stored amount that isn't a number fails to load`() async throws {
        let id = ExperimentID()
        try await repository.save(Experiment(cashBalance: Money(1)), as: id)
        try await queue.write { database in
            try database.execute(sql: "UPDATE experiment SET cash_balance = '12abc'")
        }

        let corrupt = ExperimentRepositoryError.corrupt(id, detail: "cash balance \"12abc\" isn't a valid amount")
        await #expect(throws: corrupt) {
            try await repository.load(id)
        }
    }

    @Test func `opening the same database twice leaves its data alone`() async throws {
        let id = ExperimentID()
        let experiment = try makeFullExperiment()
        try await repository.save(experiment, as: id)

        let reopened = try GRDBExperimentRepository(writer: queue)

        #expect(try await reopened.load(id) == experiment)
    }

    @Test func `a database that can't be opened throws an error naming the path`() throws {
        let url = URL(filePath: "/dev/null/Investment Simulator/experiments.sqlite")

        let error = try #require(throws: ExperimentDatabaseError.self) {
            try ExperimentDatabase.open(at: url)
        }

        guard case let .cannotOpen(path, _) = error else {
            Issue.record("Expected cannotOpen, got \(error)")
            return
        }
        #expect(path == url.path)
        #expect(error.localizedDescription.contains(url.path))
    }

    /// The one test that touches disk: SQLite only notices a file isn't a
    /// database when it reads it, and an in-memory database can't be one.
    @Test func `a file that isn't a database is reported as unopenable, not as a failed update`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "experiments.sqlite")
        try Data("This is not a database, just text. ".utf8).write(to: url)

        let error = try #require(throws: ExperimentDatabaseError.self) {
            try ExperimentDatabase.open(at: url)
        }

        guard case let .cannotOpen(path, underlying) = error else {
            Issue.record("Expected cannotOpen, got \(error)")
            return
        }
        #expect(path == url.path)
        #expect(underlying.contains("not a database"), "underlying was \(underlying)")
    }
}
