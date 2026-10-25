import Foundation
import InvestmentSimulatorCore
import Testing

struct ExperimentTests {
    @Test(arguments: ["0", "0.01", "10000", "1234567.89"])
    func `experiment starts with a non-negative cash balance`(amount: String) throws {
        let cashBalance = try Money(#require(Decimal(string: amount)))

        let experiment = try Experiment(cashBalance: cashBalance)

        #expect(experiment.cashBalance == cashBalance)
    }

    @Test func `empty experiment has a zero cash balance`() {
        #expect(Experiment.empty.cashBalance == .zero)
    }

    @Test func `negative cash balance is rejected`() throws {
        let cashBalance = try Money(#require(Decimal(string: "-0.01")))

        #expect(throws: ExperimentError.negativeCashBalance(cashBalance)) {
            try Experiment(cashBalance: cashBalance)
        }
    }

    @Test func `new experiment has no purchases`() throws {
        #expect(try Experiment(cashBalance: Money(100)).purchases.isEmpty)
        #expect(Experiment.empty.purchases.isEmpty)
    }

    @Test func `purchasing deducts the cost and records the purchase`() throws {
        let experiment = try Experiment(cashBalance: Money(1000))
        let purchase = try makePurchase(shares: 2, price: "250.10")

        let updated = try experiment.purchasing(purchase)

        #expect(try updated.cashBalance == Money(#require(Decimal(string: "499.80"))))
        #expect(updated.purchases == [purchase])
    }

    @Test func `repeat purchases of a ticker are kept separately`() throws {
        let first = try makePurchase(shares: 1, price: "10")
        let second = try makePurchase(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            shares: 1,
            price: "12",
        )

        let updated = try Experiment(cashBalance: Money(100)).purchasing(first).purchasing(second)

        #expect(updated.purchases == [first, second])
        #expect(updated.cashBalance == Money(78))
    }

    @Test func `purchase can spend all the cash`() throws {
        let updated = try Experiment(cashBalance: Money(20)).purchasing(makePurchase(shares: 2, price: "10"))

        #expect(updated.cashBalance == .zero)
    }

    @Test func `purchase costing more than the cash is rejected`() throws {
        let experiment = try Experiment(cashBalance: Money(19))

        #expect(throws: ExperimentError.insufficientCash(cost: Money(20), available: Money(19))) {
            try experiment.purchasing(makePurchase(shares: 2, price: "10"))
        }
    }

    @Test func `experiment keeps the purchases it is created with`() throws {
        let purchase = try makePurchase(shares: 1, price: "10")

        let experiment = try Experiment(cashBalance: Money(5), purchases: [purchase])

        #expect(experiment.purchases == [purchase])
    }
}
