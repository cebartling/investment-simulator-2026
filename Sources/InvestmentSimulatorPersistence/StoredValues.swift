import Foundation

/// A stored value that can't be read back, such as a malformed amount.
/// `load` reports it as `ExperimentRepositoryError.corrupt`.
struct StoredValueError: Error {
    let detail: String
}

/// Text forms of the values the schema stores as TEXT (ADR-0002, ADR-0021).
enum StoredValues {
    private static let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// `Decimal` holds at most 38 significant digits.
    private static let maxSignificantDigits = 38

    static func text(_ date: Date) -> String {
        date.formatted(dateFormat)
    }

    static func date(_ string: String, what: String) throws -> Date {
        guard let date = try? dateFormat.parse(string) else {
            throw StoredValueError(detail: "\(what) \"\(string)\" isn't a valid date")
        }
        return date
    }

    /// `Decimal(string:)` accepts a numeric prefix ("12abc" is 12) and
    /// silently rounds past 38 significant digits, so the whole string is
    /// checked against a plain decimal pattern and the digit limit first.
    static func decimal(_ string: String, what: String) throws -> Decimal {
        guard let match = string.wholeMatch(of: /-?0*([0-9]+(?:\.[0-9]+)?)/),
              significantDigits(in: match.1) <= maxSignificantDigits,
              let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
        else {
            throw StoredValueError(detail: "\(what) \"\(string)\" isn't a valid amount")
        }
        return value
    }

    static func uuid(_ string: String, what: String) throws -> UUID {
        guard let uuid = UUID(uuidString: string) else {
            throw StoredValueError(detail: "\(what) \"\(string)\" isn't a valid id")
        }
        return uuid
    }

    /// Digits between the first and last nonzero digit; zeros outside them
    /// only move the exponent.
    private static func significantDigits(in digits: Substring) -> Int {
        let digits = digits.filter(\.isNumber)
        guard let first = digits.firstIndex(where: { $0 != "0" }),
              let last = digits.lastIndex(where: { $0 != "0" })
        else {
            return 0
        }
        return digits.distance(from: first, to: last) + 1
    }
}
