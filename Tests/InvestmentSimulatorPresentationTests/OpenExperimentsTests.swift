import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct OpenExperimentsTests {
    @Test func `lists no experiments to begin with`() {
        #expect(OpenExperiments().entries.isEmpty)
    }

    @Test func `lists experiments in the order opened`() throws {
        let experiments = OpenExperiments()

        try experiments.register(makeWindow(), title: "Growth")
        try experiments.register(makeWindow(), title: "Income")

        #expect(experiments.entries.map(\.title) == ["Growth", "Income"])
    }

    @Test func `registering a window again changes its title, keeping its place`() throws {
        let experiments = OpenExperiments()
        let growth = try makeWindow()
        experiments.register(growth, title: "Untitled")
        try experiments.register(makeWindow(), title: "Income")

        experiments.register(growth, title: "Growth")

        #expect(experiments.entries.map(\.title) == ["Growth", "Income"])
    }

    @Test func `removes a closed window`() throws {
        let experiments = OpenExperiments()
        let growth = try makeWindow()
        let income = try makeWindow()
        experiments.register(growth, title: "Growth")
        experiments.register(income, title: "Income")

        experiments.remove(growth)

        #expect(experiments.entries.map(\.title) == ["Income"])
    }

    @Test func `an entry leads to its window's model`() throws {
        let experiments = OpenExperiments()
        let growth = try makeWindow()
        experiments.register(growth, title: "Growth")

        try experiments.entries.first?.model.beginPurchase(of: Ticker("VTI"))

        #expect(growth.purchase?.tickerText == "VTI")
    }

    private func makeWindow() throws -> MainWindowModel {
        try MainWindowModel(
            experiment: Experiment(cashBalance: Money(100)),
            needsSetup: false,
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: FakeDailyPrices(),
            clock: { fixedNow },
        )
    }
}
