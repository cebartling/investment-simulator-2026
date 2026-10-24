import InvestmentSimulatorPresentation
import Testing

@MainActor
struct MainWindowModelTests {
    @Test func `sections are scenario, simulation, results in order`() {
        let model = MainWindowModel()

        #expect(model.sections == [.scenario, .simulation, .results])
    }

    @Test func `initial selection is the first section`() {
        let model = MainWindowModel()

        #expect(model.selection == .scenario)
    }

    @Test(arguments: [
        (NavigationSection.scenario, "Scenario"),
        (.simulation, "Simulation"),
        (.results, "Results"),
    ])
    func `section title`(section: NavigationSection, title: String) {
        #expect(section.title == title)
    }
}
