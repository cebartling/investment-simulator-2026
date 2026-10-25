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

    /// `Decimal` holds at most 38 significant digits.
    private static let maxSignificantDigits = 38

    /// `Decimal(string:)` accepts a numeric prefix ("12abc" is 12) and
    /// silently rounds past 38 significant digits, so the whole string is
    /// checked against a plain decimal pattern and the digit limit first.
    private func decimal(from string: String) throws -> Decimal {
        guard let match = string.wholeMatch(of: /-?0*([0-9]+(?:\.[0-9]+)?)/),
              significantDigits(in: match.1) <= Self.maxSignificantDigits,
              let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
        else {
            throw ExperimentCodingError.invalidCashBalance(string)
        }
        return value
    }

    /// Digits between the first and last nonzero digit; zeros outside them
    /// only move the exponent.
    private func significantDigits(in digits: Substring) -> Int {
        let digits = digits.filter(\.isNumber)
        guard let first = digits.firstIndex(where: { $0 != "0" }),
              let last = digits.lastIndex(where: { $0 != "0" })
        else {
            return 0
        }
        return digits.distance(from: first, to: last) + 1
    }
}

public enum ExperimentCodingError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidCashBalance(String)
}

/// Shown by the document system when a file can't be opened.
extension ExperimentCodingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            "The experiment uses file format version \(version), which this version of Investment Simulator can't read."
        case let .invalidCashBalance(cashBalance):
            "The experiment's cash balance \"\(cashBalance)\" isn't a valid amount."
        }
    }

    public var failureReason: String? {
        errorDescription
    }
}

/// Core doesn't format display strings (ADR-0002), so the adapter that
/// reads files describes the domain errors a file can trigger.
extension ExperimentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .negativeCashBalance:
            "The experiment's cash balance can't be negative."
        case .insufficientCash:
            "The purchase costs more than the experiment's cash balance."
        }
    }

    public var failureReason: String? {
        errorDescription
    }
}
