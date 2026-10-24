import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct NewExperimentModelTests {
    @Test func `cash balance starts at zero and can be created`() {
        let model = NewExperimentModel()

        #expect(model.cashBalance == 0)
        #expect(model.canCreate)
        #expect(model.validationMessage == nil)
    }

    @Test func `negative cash balance cannot be created`() {
        let model = NewExperimentModel()

        model.cashBalance = -1

        #expect(!model.canCreate)
        #expect(model.validationMessage == "Cash balance can't be negative.")
    }

    @Test func `negative cash balance throws on create`() {
        let model = NewExperimentModel()
        model.cashBalance = -1

        #expect(throws: ExperimentError.negativeCashBalance(Money(-1))) {
            try model.create()
        }
    }

    @Test(arguments: [
        ("10000", "10000"),
        ("10.015", "10.02"),
        ("10.125", "10.12"),
    ])
    func `created experiment has the cash balance rounded to cents`(entered: String, expected: String) throws {
        let model = NewExperimentModel()
        model.cashBalance = try #require(Decimal(string: entered))

        let experiment = try model.create()

        #expect(try experiment.cashBalance == Money(#require(Decimal(string: expected))))
    }
}
