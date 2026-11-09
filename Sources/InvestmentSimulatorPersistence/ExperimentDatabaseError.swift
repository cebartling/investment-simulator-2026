import Foundation

/// Why the experiment database couldn't be opened (ADR-0021). The app shows
/// the message and stops: it never continues with an empty or partial store.
public enum ExperimentDatabaseError: Error, Equatable, LocalizedError {
    case cannotOpen(path: String, underlying: String)
    case migrationFailed(path: String, underlying: String)
    /// A newer version of the app migrated it. This version would drop what
    /// it doesn't know on save, so it doesn't open it (ADR-0026).
    case newerThanApp(path: String)

    public var errorDescription: String? {
        switch self {
        case let .cannotOpen(path, underlying):
            "The experiment database at \(path) couldn't be opened: \(underlying)"
        case let .migrationFailed(path, underlying):
            "The experiment database at \(path) couldn't be updated to the current version: \(underlying)"
        case let .newerThanApp(path):
            "The experiment database at \(path) was updated by a newer version of Investment Simulator. "
                + "Open it with that version, so this one doesn't lose what it can't read."
        }
    }
}
