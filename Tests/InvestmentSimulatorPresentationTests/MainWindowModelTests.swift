import InvestmentSimulatorPresentation
import Testing

@MainActor
struct MainWindowModelTests {
    @Test func `sections are experiment, simulation, results in order`() {
        let model = MainWindowModel()

        #expect(model.sections == [.experiment, .simulation, .results])
    }

    @Test func `initial selection is the first section`() {
        let model = MainWindowModel()

        #expect(model.selection == .experiment)
    }

    @Test(arguments: [
        (NavigationSection.experiment, "Experiment"),
        (.simulation, "Simulation"),
        (.results, "Results"),
    ])
    func `section title`(section: NavigationSection, title: String) {
        #expect(section.title == title)
    }
}
