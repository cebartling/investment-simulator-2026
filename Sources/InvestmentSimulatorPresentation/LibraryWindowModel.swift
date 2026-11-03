import InvestmentSimulatorCore
import Observation

/// Drives the single library window (ADR-0021): what its detail shows, and
/// the model of each experiment shown. `LibraryModel` keeps the list and its
/// actions; this adds Research as a destination and routes a purchase from
/// Research into an experiment.
@Observable
public final class LibraryWindowModel {
    public enum Destination: Hashable {
        case research
        case experiment(ExperimentID)
    }

    public let library: LibraryModel

    private let makeExperimentModel: (ExperimentID) -> MainWindowModel
    private var experimentModels: [ExperimentID: MainWindowModel] = [:]
    private var loads: [ExperimentID: Task<Void, Never>] = [:]
    private var showsResearch = false
    private var isCreating = false

    /// The New Experiment sheet's input while the sheet shows, else nil.
    public private(set) var newExperiment: NewExperimentModel?

    public init(library: LibraryModel, makeExperimentModel: @escaping (ExperimentID) -> MainWindowModel) {
        self.library = library
        self.makeExperimentModel = makeExperimentModel
    }

    /// What the detail shows, or nil with nothing selected. Backs the
    /// sidebar's selection.
    public var destination: Destination? {
        get {
            if showsResearch {
                return .research
            }
            return library.selection.map { .experiment($0) }
        }
        set {
            switch newValue {
            case .research:
                showsResearch = true
                library.selection = nil
            case let .experiment(id):
                showsResearch = false
                library.selection = id
            case nil:
                showsResearch = false
                library.selection = nil
            }
        }
    }

    /// The same model every time for one experiment, so a sheet being filled
    /// in survives switching to another experiment and back.
    public func experimentModel(for id: ExperimentID) -> MainWindowModel {
        if let model = experimentModels[id] {
            return model
        }
        let model = makeExperimentModel(id)
        experimentModels[id] = model
        return model
    }

    /// Reads the experiment from the repository the first time. A failed
    /// read is tried again by the next call, and `loadError` says why.
    public func ensureLoaded(_ id: ExperimentID) async {
        let model = experimentModel(for: id)
        let load: Task<Void, Never>
        if let running = loads[id] {
            load = running
        } else {
            load = Task { await model.load() }
            loads[id] = load
        }
        await load.value
        if model.loadError != nil {
            loads[id] = nil
        }
    }

    public func beginNewExperiment() {
        newExperiment = NewExperimentModel()
    }

    public func cancelNewExperiment() {
        newExperiment = nil
    }

    /// Creates the experiment `input` describes and shows it. Does nothing
    /// while the cash is invalid or another create is running. A failure to
    /// store it keeps the sheet open, with `library.errorMessage` saying
    /// why; once it is stored the sheet closes whatever the reload does.
    public func create(_ input: NewExperimentModel) async {
        guard !isCreating, let started = input.create() else {
            return
        }
        isCreating = true
        defer { isCreating = false }
        if await library.create(name: input.name, cashBalance: started.cashBalance) != nil {
            showsResearch = false
            newExperiment = nil
        }
    }

    /// Renames the experiment, and its model when it has one: saving writes
    /// the whole experiment, so a model left with the old name would undo
    /// the rename at its next change.
    public func rename(_ id: ExperimentID, to name: String?) async {
        await experimentModels[id]?.settleSaves()
        await library.rename(id, to: name)
        if library.errorMessage == nil, let summary = library.summaries.first(where: { $0.id == id }) {
            experimentModels[id]?.applyName(summary.name)
        }
    }

    /// Lists the library again once the saves of experiment `id` have
    /// landed, for a change made in its own window, like Edit Details,
    /// that the list shows.
    public func refreshSummaries(after id: ExperimentID) async {
        await experimentModels[id]?.settleSaves()
        await library.load()
    }

    public func duplicate(_ id: ExperimentID) async {
        // The copy is made from what is stored, so wait for the latest changes.
        await experimentModels[id]?.settleSaves()
        await library.duplicate(id)
        showSelectionIfSucceeded()
    }

    /// Deletes the experiment waiting for confirmation, and drops its model.
    public func confirmDelete() async {
        let deleted = library.pendingDeletion?.id
        // A save still running would store the experiment again.
        if let deleted {
            await experimentModels[deleted]?.settleSaves()
        }
        await library.confirmDelete()
        if let deleted, library.errorMessage == nil {
            experimentModels[deleted] = nil
            loads[deleted] = nil
        }
    }

    /// Shows experiment `id` with Market Buy filled in for `ticker`, once
    /// the experiment is read, so the sheet sees its real cash (ADR-0021).
    public func beginPurchase(of ticker: Ticker, in id: ExperimentID) async {
        await show(id)
        experimentModel(for: id).beginPurchase(of: ticker)
    }

    public func beginBuyLimitOrder(of ticker: Ticker, in id: ExperimentID) async {
        await show(id)
        experimentModel(for: id).beginBuyLimitOrder(of: ticker)
    }

    private func show(_ id: ExperimentID) async {
        destination = .experiment(id)
        await ensureLoaded(id)
    }

    /// A create or duplicate that worked selects the new experiment, so
    /// Research gives way to it; one that failed leaves things as they were.
    private func showSelectionIfSucceeded() {
        if library.errorMessage == nil {
            showsResearch = false
        }
    }
}
