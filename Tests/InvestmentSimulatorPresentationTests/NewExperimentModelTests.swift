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

    @Test(arguments: [("-0.004", true), ("-0.006", false), ("0.004", true)])
    func `validation checks the amount rounded to cents`(entered: String, valid: Bool) throws {
        let model = NewExperimentModel()

        model.cashBalance = try #require(Decimal(string: entered))

        #expect(model.canCreate == valid)
        #expect((model.create() != nil) == valid)
    }

    @Test func `negative cash balance creates nothing`() {
        let model = NewExperimentModel()
        model.cashBalance = -1

        #expect(model.create() == nil)
    }

    @Test(arguments: [
        ("10000", "10000"),
        ("10.015", "10.02"),
        ("10.125", "10.12"),
    ])
    func `created experiment has the cash balance rounded to cents`(entered: String, expected: String) throws {
        let model = NewExperimentModel()
        model.cashBalance = try #require(Decimal(string: entered))

        let experiment = try #require(model.create())

        #expect(try experiment.cashBalance == Money(#require(Decimal(string: expected))))
    }

    @Test func `created experiment records when it was created`() throws {
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        let model = NewExperimentModel(clock: { now })
        model.cashBalance = 100

        let experiment = try #require(model.create())

        #expect(experiment.createdAt == now)
        #expect(experiment.name == nil)
        #expect(experiment.notes == nil)
    }
}
