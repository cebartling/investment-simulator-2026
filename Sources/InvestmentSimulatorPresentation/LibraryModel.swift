import Foundation
import InvestmentSimulatorCore
import Observation

/// Drives the library of experiments (ADR-0021): the list, the selection,
/// and create, rename, duplicate and delete. A repository failure becomes
/// `errorMessage`; the list keeps what it last showed.
@Observable
public final class LibraryModel {
    public private(set) var summaries: [ExperimentSummary] = []
    public var selection: ExperimentID?
    /// Why the last action failed, or nil after one that worked.
    public private(set) var errorMessage: String?
    /// The experiment waiting for the user to confirm its deletion. A delete
    /// can't be undone, so it always passes through here.
    public private(set) var pendingDeletion: ExperimentSummary?

    private let repository: any ExperimentRepository

    public init(repository: any ExperimentRepository) {
        self.repository = repository
    }

    public func title(for summary: ExperimentSummary) -> String {
        summary.name ?? Self.untitled
    }

    public func load() async {
        await attempt {
            summaries = try await repository.list()
        }
    }

    /// Stores a new, empty experiment, lists it and selects it. A blank name
    /// stores none.
    public func create(name: String?) async {
        await attempt {
            let id = ExperimentID()
            let experiment = Experiment.empty.editingDetails(name: Self.stored(name), notes: nil)
            try await repository.save(experiment, as: id)
            summaries = try await repository.list()
            selection = id
        }
    }

    public func rename(_ id: ExperimentID, to name: String?) async {
        await attempt {
            try await repository.rename(id, to: Self.stored(name))
            summaries = try await repository.list()
        }
    }

    public func duplicate(_ id: ExperimentID) async {
        await attempt {
            let copy = try await repository.duplicate(id)
            summaries = try await repository.list()
            selection = copy
        }
    }

    public func requestDelete(_ summary: ExperimentSummary) {
        pendingDeletion = summary
    }

    public func cancelDelete() {
        pendingDeletion = nil
    }

    /// Does nothing without a pending deletion. The request is dropped
    /// whether or not the delete works, so a failure doesn't leave the
    /// confirmation open.
    public func confirmDelete() async {
        guard let summary = pendingDeletion else {
            return
        }
        pendingDeletion = nil
        await attempt {
            try await repository.delete(summary.id)
            if selection == summary.id {
                selection = nil
            }
            summaries = try await repository.list()
        }
    }

    private static let untitled = "Untitled"

    private static func stored(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func attempt(_ action: () async throws -> Void) async {
        do {
            try await action()
            errorMessage = nil
        } catch let error as ExperimentRepositoryError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func message(for error: ExperimentRepositoryError) -> String {
        switch error {
        case .notFound:
            "That experiment no longer exists."
        case let .corrupt(_, detail):
            "That experiment is damaged: \(detail)"
        }
    }
}
