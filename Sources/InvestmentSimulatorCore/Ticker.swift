import Foundation

/// A listed security's symbol, such as `VTI` or `BRK.B`. Stored uppercased.
public struct Ticker: Sendable, Hashable {
    public let symbol: String

    /// Trims and uppercases `text`, then accepts 1–32 ASCII letters, digits,
    /// dots or dashes, starting with a letter or digit. The symbol goes into
    /// a URL path, so it can never be `.` or `..`.
    public init(_ text: String) throws(TickerError) {
        let symbol = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard symbol.wholeMatch(of: /[A-Z0-9][A-Z0-9.\-]{0,31}/) != nil else {
            throw .invalid(text)
        }
        self.symbol = symbol
    }

    /// Whether both name one security: a share class is spelled `BRK.B` or
    /// `BRK-B`, depending on the source.
    public func isSameSecurity(as other: Ticker) -> Bool {
        Self.comparable(symbol) == Self.comparable(other.symbol)
    }

    /// `symbol` with its share class spelled one way, to compare with others.
    static func comparable(_ symbol: String) -> String {
        symbol.replacing(".", with: "-")
    }
}

public enum TickerError: Error, Equatable {
    case invalid(String)
}
