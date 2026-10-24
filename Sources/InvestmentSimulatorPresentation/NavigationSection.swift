/// A destination in the main window's sidebar.
public nonisolated enum NavigationSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case scenario
    case simulation
    case results

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .scenario: "Scenario"
        case .simulation: "Simulation"
        case .results: "Results"
        }
    }
}
