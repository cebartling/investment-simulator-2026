import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPersistence
import Testing

struct JSONExperimentCodecTests {
    let codec = JSONExperimentCodec()

    @Test func `experiment survives a round trip`() throws {
        let experiment = try makeExperiment(cashBalance: "10000.50")

        let decoded = try codec.decode(codec.encode(experiment))

        #expect(decoded == experiment)
    }

    @Test func `cash balance keeps full decimal precision`() throws {
        let experiment = try makeExperiment(cashBalance: "1234567890.123456789")

        let decoded = try codec.decode(codec.encode(experiment))

        #expect(decoded.cashBalance == experiment.cashBalance)
    }

    @Test func `encoded file is schema version 1 with the cash balance as a string`() throws {
        let data = try codec.encode(makeExperiment(cashBalance: "10000.5"))

        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["schemaVersion"] as? Int == 1)
        #expect(json["cashBalance"] as? String == "10000.5")
    }

    @Test func `version 1 file decodes`() throws {
        let data = Data(#"{"schemaVersion": 1, "cashBalance": "250.75"}"#.utf8)

        let experiment = try codec.decode(data)

        #expect(try experiment == makeExperiment(cashBalance: "250.75"))
    }

    @Test func `unknown schema version is rejected`() {
        let data = Data(#"{"schemaVersion": 2, "cashBalance": "1"}"#.utf8)

        #expect(throws: ExperimentCodingError.unsupportedSchemaVersion(2)) {
            try codec.decode(data)
        }
    }

    @Test(arguments: [
        #"not json"#,
        #"{"cashBalance": "1"}"#,
        #"{"schemaVersion": 1}"#,
        #"{"schemaVersion": 1, "cashBalance": 1}"#,
    ])
    func `malformed file is rejected`(contents: String) {
        #expect(throws: DecodingError.self) {
            try codec.decode(Data(contents.utf8))
        }
    }

    @Test(arguments: ["", "abc", "12abc", "1,000", "1e3", "$5", " 5"])
    func `non-numeric cash balance is rejected`(cashBalance: String) {
        let data = Data(#"{"schemaVersion": 1, "cashBalance": "\#(cashBalance)"}"#.utf8)

        #expect(throws: ExperimentCodingError.invalidCashBalance(cashBalance)) {
            try codec.decode(data)
        }
    }

    @Test func `cash balance at Decimal's 38 digit limit is accepted`() throws {
        let cashBalance = String(repeating: "9", count: 38)
        let data = Data(#"{"schemaVersion": 1, "cashBalance": "\#(cashBalance)"}"#.utf8)

        let experiment = try codec.decode(data)

        #expect(experiment.cashBalance.amount.description == cashBalance)
    }

    @Test(arguments: [
        String(repeating: "9", count: 39),
        "1" + String(repeating: "0", count: 37) + ".1",
    ])
    func `cash balance with more significant digits than Decimal holds is rejected`(cashBalance: String) {
        let data = Data(#"{"schemaVersion": 1, "cashBalance": "\#(cashBalance)"}"#.utf8)

        #expect(throws: ExperimentCodingError.invalidCashBalance(cashBalance)) {
            try codec.decode(data)
        }
    }

    @Test(arguments: ["0.000", "1" + String(repeating: "0", count: 45), "00012.50"])
    func `leading and trailing zeros do not count toward the digit limit`(cashBalance: String) throws {
        let data = Data(#"{"schemaVersion": 1, "cashBalance": "\#(cashBalance)"}"#.utf8)

        let experiment = try codec.decode(data)

        #expect(try experiment.cashBalance == Money(#require(Decimal(string: cashBalance))))
    }

    @Test(arguments: [
        (
            ExperimentCodingError.unsupportedSchemaVersion(2),
            "The experiment uses file format version 2, which this version of Investment Simulator can't read.",
        ),
        (
            .invalidCashBalance("abc"),
            "The experiment's cash balance \"abc\" isn't a valid amount.",
        ),
    ])
    func `coding errors describe the problem`(error: ExperimentCodingError, description: String) {
        #expect(error.localizedDescription == description)
        // The document system's "could not be opened" alert shows the reason.
        #expect((error as NSError).localizedFailureReason == description)
    }

    @Test func `negative cash balance error describes the problem`() {
        let error: any Error = ExperimentError.negativeCashBalance(Money(-1))

        #expect(error.localizedDescription == "The experiment's cash balance can't be negative.")
        #expect((error as NSError).localizedFailureReason == "The experiment's cash balance can't be negative.")
    }

    @Test func `negative cash balance is rejected by the domain`() throws {
        let data = Data(#"{"schemaVersion": 1, "cashBalance": "-1"}"#.utf8)

        #expect(throws: ExperimentError.negativeCashBalance(Money(-1))) {
            try codec.decode(data)
        }
    }

    private func makeExperiment(cashBalance: String) throws -> Experiment {
        try Experiment(cashBalance: Money(#require(Decimal(string: cashBalance))))
    }
}
