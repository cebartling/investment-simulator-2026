/// A destination in the main window's sidebar.
public nonisolated enum NavigationSection: CaseIterable, Identifiable, Sendable {
    case experiment
    case simulation
    case results

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .experiment: "Experiment"
        case .simulation: "Simulation"
        case .results: "Results"
        }
    }
}
