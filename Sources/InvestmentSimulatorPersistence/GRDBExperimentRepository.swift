import Foundation
import GRDB
import InvestmentSimulatorCore

/// `ExperimentRepository` over a GRDB database (ADR-0021). The app passes a
/// `DatabasePool`; tests pass an in-memory `DatabaseQueue`.
public struct GRDBExperimentRepository: ExperimentRepository {
    private let writer: any DatabaseWriter

    /// Brings the database to the current schema. Does nothing to one that
    /// is already there. Throws `ExperimentDatabaseError.newerThanApp`, and
    /// changes nothing, for one a newer version of the app migrated.
    public init(writer: any DatabaseWriter) throws {
        let migrator = ExperimentSchema.migrator()
        guard try !writer.read(migrator.hasBeenSuperseded) else {
            throw ExperimentDatabaseError.newerThanApp(path: writer.path)
        }
        try migrator.migrate(writer)
        self.writer = writer
    }

    public func list() async throws -> [ExperimentSummary] {
        try await writer.read { database in
            try Row.fetchAll(database, sql: """
            SELECT id, name, created_at FROM experiment
            ORDER BY created_at IS NULL, created_at DESC, name IS NULL, name, id
            """).compactMap { row in
                // One damaged row mustn't make the whole library unlistable.
                // An unreadable name or date shows as missing, and the
                // experiment can still be deleted. A row whose id isn't an
                // id can't be named by any call, so it is left out.
                guard let uuid = try? StoredValues.uuid(row, "id", what: "experiment id") else {
                    return nil
                }
                return ExperimentSummary(
                    id: ExperimentID(uuid),
                    name: try? StoredValues.optionalText(row, "name", what: "name"),
                    createdAt: try? StoredValues.optionalDate(row, "created_at", what: "created date"),
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
            } catch let error as PurchaseError {
                throw ExperimentRepositoryError.corrupt(id, detail: String(describing: error))
            } catch let error as SaleError {
                throw ExperimentRepositoryError.corrupt(id, detail: String(describing: error))
            } catch let error as LimitOrderError {
                throw ExperimentRepositoryError.corrupt(id, detail: String(describing: error))
            } catch let error as ExperimentError {
                throw ExperimentRepositoryError.corrupt(id, detail: String(describing: error))
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
