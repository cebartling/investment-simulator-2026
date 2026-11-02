import Foundation
import GRDB
import InvestmentSimulatorCore

/// `ExperimentRepository` over a GRDB database (ADR-0021). The app passes a
/// `DatabasePool`; tests pass an in-memory `DatabaseQueue`.
public struct GRDBExperimentRepository: ExperimentRepository {
    private let writer: any DatabaseWriter

    /// Brings the database to the current schema. Does nothing to one that
    /// is already there.
    public init(writer: any DatabaseWriter) throws {
        try ExperimentSchema.migrator().migrate(writer)
        self.writer = writer
    }

    public func list() async throws -> [ExperimentSummary] {
        try await writer.read { database in
            try Row.fetchAll(database, sql: """
            SELECT id, name, created_at FROM experiment
            ORDER BY created_at IS NULL, created_at DESC, name IS NULL, name, id
            """).map { row in
                try ExperimentSummary(
                    id: ExperimentID(StoredValues.uuid(row["id"], what: "experiment id")),
                    name: row["name"],
                    createdAt: (row["created_at"] as String?).map { try StoredValues.date($0, what: "created date") },
                )
            }
        }
    }

    public func load(_ id: ExperimentID) async throws -> Experiment {
        try await writer.read { database in
            guard let header = try Row.fetchOne(
                database,
                sql: "SELECT cash_balance, name, notes, created_at FROM experiment WHERE id = ?",
                arguments: [id.rawValue.uuidString],
            ) else {
                throw ExperimentRepositoryError.notFound(id)
            }
            do {
                return try StoredExperiment.read(header: header, id: id, from: database)
            } catch let error as StoredValueError {
                throw ExperimentRepositoryError.corrupt(id, detail: error.detail)
            }
        }
    }

    public func save(_ experiment: Experiment, as id: ExperimentID) async throws {
        try await writer.write { database in
            try database.execute(sql: "DELETE FROM experiment WHERE id = ?", arguments: [id.rawValue.uuidString])
            try StoredExperiment.insert(experiment, as: id, into: database)
        }
    }

    public func rename(_ id: ExperimentID, to name: String?) async throws {
        try await writer.write { database in
            try database.execute(
                sql: "UPDATE experiment SET name = ? WHERE id = ?",
                arguments: [name, id.rawValue.uuidString],
            )
            guard database.changesCount > 0 else {
                throw ExperimentRepositoryError.notFound(id)
            }
        }
    }

    public func duplicate(_ id: ExperimentID) async throws -> ExperimentID {
        let copy = ExperimentID()
        try await writer.write { database in
            try StoredExperiment.copy(id, to: copy, in: database)
        }
        return copy
    }

    public func delete(_ id: ExperimentID) async throws {
        try await writer.write { database in
            try database.execute(sql: "DELETE FROM experiment WHERE id = ?", arguments: [id.rawValue.uuidString])
            guard database.changesCount > 0 else {
                throw ExperimentRepositoryError.notFound(id)
            }
        }
    }
}
