import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// The app's one window (ADR-0021): Research and the library of experiments
/// in the sidebar, and what is selected in the detail.
struct LibraryWindow: View {
    @Bindable var model: LibraryWindowModel
    let research: ResearchWindowModel

    @State private var renaming: ExperimentSummary?
    @State private var renameText = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        // Tall enough for the fullest grouped-form sheet (about nine rows)
        // to fit without scrolling, and for a few stock cards to show below
        // the Experiment header (PIN-405, PIN-408, ADR-0022).
        .frame(minWidth: 900, minHeight: 640)
        .task { await model.library.load() }
        .sheet(item: newExperimentBinding) { input in
            NewExperimentSheet(
                model: input.model,
                onCreate: { Task { await model.create(input.model) } },
                onCancel: model.cancelNewExperiment,
            )
        }
        .alert("Rename Experiment", isPresented: renamingBinding) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let target = renaming {
                    let name = renameText
                    Task { await model.rename(target.id, to: name) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        // The dialog is dismissed only by its buttons, so a click on Delete
        // reads the pending deletion before anything clears it.
        .confirmationDialog(
            "Delete \(model.library.pendingDeletion.map(model.library.title(for:)) ?? "this experiment")?",
            isPresented: .constant(model.library.pendingDeletion != nil),
            titleVisibility: .visible,
        ) {
            Button("Delete", role: .destructive) {
                Task { await model.confirmDelete() }
            }
            Button("Cancel", role: .cancel, action: model.library.cancelDelete)
        } message: {
            Text("This can't be undone.")
        }
    }

    private var sidebar: some View {
        List(selection: $model.destination) {
            Label("Research", systemImage: "magnifyingglass")
                .tag(LibraryWindowModel.Destination.research)
            Section("Experiments") {
                ForEach(model.library.summaries) { summary in
                    Label(model.library.title(for: summary), systemImage: "flask")
                        .tag(LibraryWindowModel.Destination.experiment(summary.id))
                        .contextMenu {
                            Button("Rename…") {
                                renameText = summary.name ?? ""
                                renaming = summary
                            }
                            Button("Duplicate") {
                                Task { await model.duplicate(summary.id) }
                            }
                            Divider()
                            Button("Delete…", role: .destructive) {
                                model.library.requestDelete(summary)
                            }
                        }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .toolbar {
            Button("New Experiment…", systemImage: "plus", action: model.beginNewExperiment)
                .help("Start a new experiment with some cash")
        }
        .safeAreaInset(edge: .bottom) {
            if let message = model.library.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.destination {
        case .research:
            ResearchView(model: research, library: model)
        case let .experiment(id):
            ExperimentView(model: model.experimentModel(for: id))
                // A fresh view per experiment, so its footer prices that experiment's holdings.
                .id(id)
                .onChange(of: model.experimentModel(for: id).experiment.name) {
                    Task { await model.refreshSummaries(after: id) }
                }
                // The model is cached, so a task per experiment reads each once.
                .task(id: id) { await model.ensureLoaded(id) }
        case nil:
            ContentUnavailableView(
                "No Selection",
                systemImage: "sidebar.left",
                description: Text("Choose an experiment, or create one."),
            )
        }
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: {
            if !$0 {
                renaming = nil
            }
        })
    }

    private var newExperimentBinding: Binding<NewExperimentItem?> {
        Binding(
            get: { model.newExperiment.map(NewExperimentItem.init) },
            set: {
                if $0 == nil {
                    model.cancelNewExperiment()
                }
            },
        )
    }
}

/// Lets `.sheet(item:)` follow the model's New Experiment input.
private struct NewExperimentItem: Identifiable {
    let model: NewExperimentModel

    var id: ObjectIdentifier {
        ObjectIdentifier(model)
    }
}

extension NewExperimentItem: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model
    }
}
