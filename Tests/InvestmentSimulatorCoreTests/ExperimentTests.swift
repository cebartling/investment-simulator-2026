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
}
