import InvestmentSimulatorCore
import Observation

/// Where a window opened from the library saves one experiment (ADR-0021).
/// Saves run one after another, so the repository sees the changes in the
/// order they were made. A failure becomes `saveError`; the window keeps the
/// change, and the next save writes the whole experiment again.
@Observable
final class ExperimentStorage {
    let id: ExperimentID
    let repository: any ExperimentRepository
    /// Why the last save failed, or nil after one that worked.
    private(set) var saveError: String?
    private var pending: Task<Void, Never>?

    init(id: ExperimentID, repository: any ExperimentRepository) {
        self.id = id
        self.repository = repository
    }

    func save(_ experiment: Experiment) {
        let previous = pending
        pending = Task {
            await previous?.value
            do {
                try await repository.save(experiment, as: id)
                saveError = nil
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    /// Waits for every save started so far.
    func settle() async {
        await pending?.value
    }
}
