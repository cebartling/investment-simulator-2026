import Foundation

/// One dividend on a ticker.
public struct Dividend: Sendable, Hashable {
    /// `yyyy-MM-dd`, which sorts as text.
    public let exDate: String
    /// As quoted, which can include fractions of a cent.
    public let amountPerShare: Decimal
    public let currency: String

    public init(exDate: String, amountPerShare: Decimal, currency: String) throws(DividendError) {
        guard isSessionDate(exDate) else {
            throw .invalidExDate(exDate)
        }
        self.exDate = exDate
        self.amountPerShare = amountPerShare
        self.currency = currency
    }
}

public enum DividendError: Error, Equatable {
    case invalidExDate(String)
}

/// Driven port for a ticker's dividends (ADR-0019). `async` because adapters
/// reach the network (ADR-0003).
public protocol DividendProviding: Sendable {
    func dividends(for ticker: Ticker) async throws(MarketDataError) -> [Dividend]
}
