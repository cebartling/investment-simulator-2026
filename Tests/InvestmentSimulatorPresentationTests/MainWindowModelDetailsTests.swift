import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// Edit Details (PIN-408).
@MainActor
struct MainWindowModelDetailsTests {
    @Test func `editing details shows the sheet with the current name and notes`() throws {
        let model = try makeModel(name: "Index funds", notes: "Hold")

        model.beginEditingDetails()

        #expect(model.isShowingDetails)
        #expect(model.details?.name == "Index funds")
        #expect(model.details?.notes == "Hold")
    }

    @Test func `saving details updates the experiment and hides the sheet`() throws {
        let model = try makeModel(name: nil, notes: nil)
        model.beginEditingDetails()
        model.details?.name = " Growth "
        model.details?.notes = "Tech"

        let updated = try #require(model.completeEditingDetails())

        #expect(updated.name == "Growth")
        #expect(updated.notes == "Tech")
        #expect(updated.createdAt == Self.created)
        #expect(model.experiment == updated)
        #expect(!model.isShowingDetails)
        #expect(model.details == nil)
    }

    @Test func `saving unchanged details returns nothing to save`() throws {
        let model = try makeModel(name: "Index funds", notes: nil)
        model.beginEditingDetails()
        model.details?.name = "Index funds "

        #expect(model.completeEditingDetails() == nil)
        #expect(!model.isShowingDetails)
    }

    @Test func `cancelling details leaves the experiment alone`() throws {
        let model = try makeModel(name: "Index funds", notes: nil)
        let experiment = model.experiment
        model.beginEditingDetails()
        model.details?.name = "Growth"

        model.cancelEditingDetails()

        #expect(model.experiment == experiment)
        #expect(!model.isShowingDetails)
        #expect(model.details == nil)
    }

    private static let created = Date(timeIntervalSince1970: 1_792_000_000)

    private func makeModel(name: String?, notes: String?) throws -> MainWindowModel {
        try MainWindowModel(
            experiment: Experiment(cashBalance: Money(100), name: name, notes: notes, createdAt: Self.created),
            needsSetup: false,
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: FakeDailyPrices(),
        )
    }
}
