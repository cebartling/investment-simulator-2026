import Observation

/// Drives the main window: the sidebar's sections and which one is shown.
@Observable
public final class MainWindowModel {
    public let sections = NavigationSection.allCases
    public var selection: NavigationSection? = .scenario

    public init() {}
}
