import Foundation
import InvestmentSimulatorCore
import Testing

/// An experiment's name, notes and created date (PIN-408).
struct ExperimentDetailsTests {
    @Test func `new experiment has no name, notes or created date`() throws {
        let experiment = try Experiment(cashBalance: Money(100))

        #expect(experiment.name == nil)
        #expect(experiment.notes == nil)
        #expect(experiment.createdAt == nil)
        #expect(Experiment.empty.name == nil)
        #expect(Experiment.empty.createdAt == nil)
    }

    @Test func `experiment keeps the details it is created with`() throws {
        let experiment = try detailed()

        #expect(experiment.name == "Index funds")
        #expect(experiment.notes == "Buy and hold.")
        #expect(experiment.createdAt == Self.created)
    }

    @Test func `editing details replaces the name and notes and keeps the rest`() throws {
        let experiment = try detailed().purchasing(makePurchase(shares: 1, price: "10"), at: Self.now)

        let edited = experiment.editingDetails(name: "Growth", notes: nil)

        #expect(edited.name == "Growth")
        #expect(edited.notes == nil)
        #expect(edited.createdAt == Self.created)
        #expect(edited.cashBalance == experiment.cashBalance)
        #expect(edited.purchases == experiment.purchases)
    }

    @Test func `purchases and orders keep the details`() throws {
        let sell = try makeLimitOrder(shares: 1)
        let buy = try makeBuyLimitOrder(shares: 1, limitPrice: "9")
        let cancelled = try makeBuyLimitOrder(id: Self.secondBuyID, shares: 1, limitPrice: "9")
        let experiment = try detailed()
            .purchasing(makePurchase(shares: 2, price: "10"), at: Self.now)
            .placing(sell)
            .placing(buy)
            .placing(cancelled)
            .filling(orderID: sell.id, on: "2026-10-23")
            .fillingBuyOrder(orderID: buy.id, on: "2026-10-23")
            .cancelling(orderID: cancelled.id, at: Self.now.addingTimeInterval(60))

        #expect(experiment.name == "Index funds")
        #expect(experiment.notes == "Buy and hold.")
        #expect(experiment.createdAt == Self.created)
    }

    @Test func `rebuilding with sell orders keeps the details`() throws {
        let experiment = try Experiment(
            cashBalance: Money(90),
            purchases: [makePurchase(shares: 1, price: "10")],
            limitOrders: [makeLimitOrder(shares: 1)],
            name: "Index funds",
            notes: "Buy and hold.",
            createdAt: Self.created,
        )

        #expect(experiment.name == "Index funds")
        #expect(experiment.createdAt == Self.created)
    }

    private static let now = Date(timeIntervalSince1970: 1_793_000_000)
    private static let created = Date(timeIntervalSince1970: 1_792_000_000)
    private static let secondBuyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!

    private func detailed() throws -> Experiment {
        try Experiment(cashBalance: Money(1000), name: "Index funds", notes: "Buy and hold.", createdAt: Self.created)
    }
}
