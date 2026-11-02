import Foundation
import GRDB

/// A stored value that can't be read back, such as a malformed amount.
/// `load` reports it as `ExperimentRepositoryError.corrupt`.
struct StoredValueError: Error {
    let detail: String
}

/// Reads and writes the values the schema stores (ADR-0002, ADR-0021).
/// SQLite columns are dynamically typed, so every read goes through
/// `DatabaseValue` and throws on a value of the wrong type. GRDB's own
/// subscripts would stop the app instead.
enum StoredValues {
    /// `Decimal` holds at most 38 significant digits.
    private static let maxSignificantDigits = 38

    // MARK: Writing

    /// Dates are stored as REAL seconds since the reference date: the same
    /// `Double` `Date` holds, so a date comes back exactly, to the last bit.
    static func stored(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate
    }

    // MARK: Reading

    static func text(_ row: Row, _ column: String, what: String) throws -> String {
        guard let text = String.fromDatabaseValue(row[column]) else {
            throw StoredValueError(detail: "\(what) isn't text")
        }
        return text
    }

    static func optionalText(_ row: Row, _ column: String, what: String) throws -> String? {
        try row[column] == DatabaseValue.null ? nil : text(row, column, what: what)
    }

    static func integer(_ row: Row, _ column: String, what: String) throws -> Int {
        guard let number = Int.fromDatabaseValue(row[column]) else {
            throw StoredValueError(detail: "\(what) isn't a whole number")
        }
        return number
    }

    static func optionalBool(_ row: Row, _ column: String, what: String) throws -> Bool? {
        guard row[column] != DatabaseValue.null else {
            return nil
        }
        guard let flag = Bool.fromDatabaseValue(row[column]) else {
            throw StoredValueError(detail: "\(what) isn't true or false")
        }
        return flag
    }

    static func date(_ row: Row, _ column: String, what: String) throws -> Date {
        guard let seconds = Double.fromDatabaseValue(row[column]) else {
            throw StoredValueError(detail: "\(what) isn't a valid date")
        }
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    static func optionalDate(_ row: Row, _ column: String, what: String) throws -> Date? {
        try row[column] == DatabaseValue.null ? nil : date(row, column, what: what)
    }

    static func uuid(_ row: Row, _ column: String, what: String) throws -> UUID {
        let string = try text(row, column, what: what)
        guard let uuid = UUID(uuidString: string) else {
            throw StoredValueError(detail: "\(what) \"\(string)\" isn't a valid id")
        }
        return uuid
    }

    /// `Decimal(string:)` accepts a numeric prefix ("12abc" is 12) and
    /// silently rounds past 38 significant digits, so the whole string is
    /// checked against a plain decimal pattern and the digit limit first.
    static func decimal(_ row: Row, _ column: String, what: String) throws -> Decimal {
        let string = try text(row, column, what: what)
        guard let match = string.wholeMatch(of: /-?0*([0-9]+(?:\.[0-9]+)?)/),
              significantDigits(in: match.1) <= maxSignificantDigits,
              let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
        else {
            throw StoredValueError(detail: "\(what) \"\(string)\" isn't a valid amount")
        }
        return value
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
