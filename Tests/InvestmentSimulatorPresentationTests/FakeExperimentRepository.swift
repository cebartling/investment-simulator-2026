import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Synchronization

/// Keeps experiments in memory, in the order `list()` promises: newest
/// `createdAt` first, then name, then id. `failNext(with:)` makes the next
/// call throw, whichever it is; `afterCalls` lets that many calls through
/// first.
final class FakeExperimentRepository: ExperimentRepository {
    private struct State {
        var experiments: [ExperimentID: Experiment] = [:]
        var failure: (any Error)?
        var callsBeforeFailure = 0
        var savedCount = 0
    }

    private let state = Mutex(State())

    init(_ experiments: [ExperimentID: Experiment] = [:]) {
        state.withLock { $0.experiments = experiments }
    }

    func failNext(with error: any Error, afterCalls: Int = 0) {
        state.withLock {
            $0.failure = error
            $0.callsBeforeFailure = afterCalls
        }
    }

    var savedCount: Int {
        state.withLock { $0.savedCount }
    }

    func stored(_ id: ExperimentID) -> Experiment? {
        state.withLock { $0.experiments[id] }
    }

    func list() async throws -> [ExperimentSummary] {
        try state.withLock { state in
            try Self.throwScriptedFailure(&state)
            return state.experiments
                .map { ExperimentSummary(id: $0.key, name: $0.value.name, createdAt: $0.value.createdAt) }
                .sorted(by: Self.listsBefore)
        }
    }

    func load(_ id: ExperimentID) async throws -> Experiment {
        try state.withLock { state in
            try Self.throwScriptedFailure(&state)
            guard let experiment = state.experiments[id] else {
                throw ExperimentRepositoryError.notFound(id)
            }
            return experiment
        }
    }

    func save(_ experiment: Experiment, as id: ExperimentID) async throws {
        try state.withLock { state in
            try Self.throwScriptedFailure(&state)
            state.experiments[id] = experiment
            state.savedCount += 1
        }
    }

    func rename(_ id: ExperimentID, to name: String?) async throws {
        try state.withLock { state in
            try Self.throwScriptedFailure(&state)
            guard let experiment = state.experiments[id] else {
                throw ExperimentRepositoryError.notFound(id)
            }
            state.experiments[id] = experiment.editingDetails(name: name, notes: experiment.notes)
        }
    }

    func duplicate(_ id: ExperimentID) async throws -> ExperimentID {
        try state.withLock { state in
            try Self.throwScriptedFailure(&state)
            guard let experiment = state.experiments[id] else {
                throw ExperimentRepositoryError.notFound(id)
            }
            let copy = ExperimentID()
            state.experiments[copy] = experiment
            return copy
        }
    }

    func delete(_ id: ExperimentID) async throws {
        try state.withLock { state in
            try Self.throwScriptedFailure(&state)
            guard state.experiments.removeValue(forKey: id) != nil else {
                throw ExperimentRepositoryError.notFound(id)
            }
        }
    }

    private static func throwScriptedFailure(_ state: inout State) throws {
        if let failure = state.failure {
            if state.callsBeforeFailure > 0 {
                state.callsBeforeFailure -= 1
                return
            }
            state.failure = nil
            throw failure
        }
    }

    private static func listsBefore(_ lhs: ExperimentSummary, _ rhs: ExperimentSummary) -> Bool {
        switch (lhs.createdAt, rhs.createdAt) {
        case let (left?, right?) where left != right:
            return left > right
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            break
        }
        if lhs.name != rhs.name {
            return (lhs.name ?? "") < (rhs.name ?? "")
        }
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }
}

/// A model of `experiment`, stored in a fake repository and loaded, as the
/// library window shows it.
@MainActor
func loadedModel(
    experiment: Experiment,
    quotes: any QuoteProviding,
    dailyPrices: any DailyPriceProviding,
    profiles: any CompanyProfileProviding = FakeResearchData(),
    clock: @escaping () -> Date = Date.init,
) async -> MainWindowModel {
    let id = ExperimentID()
    let model = MainWindowModel(
        id: id,
        repository: FakeExperimentRepository([id: experiment]),
        quotes: quotes,
        dailyPrices: dailyPrices,
        profiles: profiles,
        clock: clock,
    )
    await model.load()
    return model
}
