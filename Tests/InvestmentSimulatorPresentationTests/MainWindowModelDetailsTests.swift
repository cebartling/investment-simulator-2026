import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// The Experiment header and Edit Details (PIN-408).
@MainActor
struct MainWindowModelDetailsTests {
    @Test func `editing details shows the sheet with the current name and notes`() async throws {
        let model = try await makeModel(name: "Index funds", notes: "Hold")

        model.beginEditingDetails()

        #expect(model.isShowingDetails)
        #expect(model.details?.name == "Index funds")
        #expect(model.details?.notes == "Hold")
    }

    @Test func `saving details updates the experiment and hides the sheet`() async throws {
        let model = try await makeModel(name: nil, notes: nil)
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

    @Test func `saving unchanged details returns nothing to save`() async throws {
        let model = try await makeModel(name: "Index funds", notes: nil)
        model.beginEditingDetails()
        model.details?.name = "Index funds "

        #expect(model.completeEditingDetails() == nil)
        #expect(!model.isShowingDetails)
    }

    @Test func `cancelling details leaves the experiment alone`() async throws {
        let model = try await makeModel(name: "Index funds", notes: nil)
        let experiment = model.experiment
        model.beginEditingDetails()
        model.details?.name = "Growth"

        model.cancelEditingDetails()

        #expect(model.experiment == experiment)
        #expect(!model.isShowingDetails)
        #expect(model.details == nil)
    }

    @Test func `title is the experiment's name`() async throws {
        let model = try await makeModel(name: "Index funds", notes: nil)

        #expect(model.title == "Index funds")
    }

    @Test func `title of an unnamed experiment is untitled`() async throws {
        #expect(try await makeModel(name: nil, notes: nil).title == "Untitled")
    }

    @Test func `available cash leaves out what open buy orders reserve`() async throws {
        let order = try BuyLimitOrder.placed(
            id: UUID(),
            ticker: Ticker("VTI"),
            shares: 4,
            limitPrice: Money(9),
            at: fixedNow,
        )
        let model = try await loadedModel(experiment: Experiment(cashBalance: Money(100)).placing(order),
                                          quotes: FakeQuotes(.failure(.missingAPIKey)),
                                          dailyPrices: FakeDailyPrices(),
                                          clock: { fixedNow })

        #expect(model.availableCash(at: fixedNow) == 64)
        #expect(model.availableCash(at: order.expiresAt) == 100)
    }

    private static let created = Date(timeIntervalSince1970: 1_792_000_000)

    private func makeModel(name: String?, notes: String?) async throws -> MainWindowModel {
        try await loadedModel(
            experiment: Experiment(cashBalance: Money(100), name: name, notes: notes, createdAt: Self.created),
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: FakeDailyPrices(),
        )
    }
}
