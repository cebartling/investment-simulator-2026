import Foundation
import GRDB

/// Opens the app-wide experiment database (ADR-0021).
public enum ExperimentDatabase {
    /// `~/Library/Application Support/Investment Simulator/experiments.sqlite`.
    public static func defaultURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Investment Simulator", directoryHint: .isDirectory)
            .appending(path: "experiments.sqlite", directoryHint: .notDirectory)
    }

    /// Opens, creating it if need be, the database at `url` as a
    /// `DatabasePool` and brings it to the current schema. Throws
    /// `ExperimentDatabaseError` naming the path; nothing is recreated or skipped.
    public static func open(at url: URL) throws -> GRDBExperimentRepository {
        let path = url.path
        let pool: DatabasePool
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            pool = try DatabasePool(path: path)
        } catch {
            throw ExperimentDatabaseError.cannotOpen(path: path, underlying: String(describing: error))
        }
        do {
            return try GRDBExperimentRepository(writer: pool)
        } catch {
            throw ExperimentDatabaseError.migrationFailed(path: path, underlying: String(describing: error))
        }
    }
}
