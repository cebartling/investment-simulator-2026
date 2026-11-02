import Foundation

/// Names one stored experiment. Callers make the id when they create an
/// experiment, so saving a new one and updating an old one are the same call.
public struct ExperimentID: Sendable, Hashable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// What the library lists for one experiment, without loading its history.
/// Core holds no display text: the title's "Untitled" fallback is the
/// presentation layer's (ADR-0015, ADR-0021).
public struct ExperimentSummary: Sendable, Hashable, Identifiable {
    public let id: ExperimentID
    public let name: String?
    public let createdAt: Date?

    public init(id: ExperimentID, name: String?, createdAt: Date?) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// Driven port for the app-wide library of experiments (ADR-0021).
public protocol ExperimentRepository: Sendable {
    /// Newest `createdAt` first, experiments without one last, ties by name
    /// and then id so the order is stable. A damaged row doesn't fail the
    /// list: an unreadable name or date comes back nil, so the experiment
    /// can still be deleted, and a row with an unreadable id is left out.
    func list() async throws -> [ExperimentSummary]

    /// Throws `ExperimentRepositoryError.notFound` for an unknown id.
    func load(_ id: ExperimentID) async throws -> Experiment

    /// Stores the whole experiment under `id`, replacing any earlier one.
    func save(_ experiment: Experiment, as id: ExperimentID) async throws

    /// Changes only the name; nil clears it. Throws `notFound` for an
    /// unknown id.
    func rename(_ id: ExperimentID, to name: String?) async throws

    /// Stores a copy under a new id and returns it. Throws `notFound` for an
    /// unknown id.
    func duplicate(_ id: ExperimentID) async throws -> ExperimentID

    /// Permanent: there is no undo (ADR-0021). Throws `notFound` for an
    /// unknown id.
    func delete(_ id: ExperimentID) async throws
}

public enum ExperimentRepositoryError: Error, Equatable {
    case notFound(ExperimentID)
    /// A stored row that doesn't make a valid experiment.
    case corrupt(ExperimentID, detail: String)
}
