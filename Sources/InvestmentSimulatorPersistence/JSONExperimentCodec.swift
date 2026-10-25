import Foundation
import InvestmentSimulatorCore

/// Maps an `Experiment` to and from the versioned `.invsim` JSON format.
public struct JSONExperimentCodec: ExperimentCoding {
    public init() {}

    public func encode(_ experiment: Experiment) throws -> Data {
        let document = ExperimentDocumentV1(
            schemaVersion: ExperimentDocumentV1.schemaVersion,
            cashBalance: experiment.cashBalance.amount.description,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    public func decode(_ data: Data) throws -> Experiment {
        let decoder = JSONDecoder()
        let version = try decoder.decode(SchemaVersionProbe.self, from: data).schemaVersion
        guard version == ExperimentDocumentV1.schemaVersion else {
            throw ExperimentCodingError.unsupportedSchemaVersion(version)
        }
        let document = try decoder.decode(ExperimentDocumentV1.self, from: data)
        return try Experiment(cashBalance: Money(decimal(from: document.cashBalance)))
    }

    /// `Decimal(string:)` accepts a numeric prefix ("12abc" is 12), so the
    /// whole string is checked against a plain decimal pattern first.
    private func decimal(from string: String) throws -> Decimal {
        guard string.wholeMatch(of: /-?[0-9]+(\.[0-9]+)?/) != nil,
              let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
        else {
            throw ExperimentCodingError.invalidCashBalance(string)
        }
        return value
    }
}

public enum ExperimentCodingError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidCashBalance(String)
}
