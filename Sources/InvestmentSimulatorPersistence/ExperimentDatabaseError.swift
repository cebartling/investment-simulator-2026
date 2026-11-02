import Foundation

/// Why the experiment database couldn't be opened (ADR-0021). The app shows
/// the message and stops: it never continues with an empty or partial store.
public enum ExperimentDatabaseError: Error, Equatable, LocalizedError {
    case cannotOpen(path: String, underlying: String)
    case migrationFailed(path: String, underlying: String)

    public var errorDescription: String? {
        switch self {
        case let .cannotOpen(path, underlying):
            "The experiment database at \(path) couldn't be opened: \(underlying)"
        case let .migrationFailed(path, underlying):
            "The experiment database at \(path) couldn't be updated to the current version: \(underlying)"
        }
    }
}
