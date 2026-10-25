import Foundation

/// A listed security's symbol, such as `VTI` or `BRK.B`. Stored uppercased.
public struct Ticker: Sendable, Hashable {
    public let symbol: String

    /// Trims and uppercases `text`, then accepts 1–32 ASCII letters, digits,
    /// dots or dashes, the same symbols the market data source accepts.
    public init(_ text: String) throws(TickerError) {
        let symbol = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard symbol.wholeMatch(of: /[A-Z0-9.\-]{1,32}/) != nil else {
            throw .invalid(text)
        }
        self.symbol = symbol
    }
}

public enum TickerError: Error, Equatable {
    case invalid(String)
}
