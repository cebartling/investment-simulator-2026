import Foundation

/// One session's prices for one share of a ticker, as quoted, which can
/// include fractions of a cent.
public struct DailyBar: Sendable, Hashable {
    /// The session's date in New York, `yyyy-MM-dd`, so dates sort as text.
    public let sessionDate: String
    public let open: Decimal
    public let high: Decimal
    public let low: Decimal
    public let close: Decimal

    public init(
        sessionDate: String,
        open: Decimal,
        high: Decimal,
        low: Decimal,
        close: Decimal,
    ) throws(DailyBarError) {
        guard isSessionDate(sessionDate) else {
            throw .invalidSessionDate(sessionDate)
        }
        guard low > 0 else {
            throw .nonPositivePrice(low)
        }
        guard low <= open, open <= high, low <= close, close <= high else {
            throw .inconsistentPrices
        }
        self.sessionDate = sessionDate
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }
}

public enum DailyBarError: Error, Equatable {
    case invalidSessionDate(String)
    case nonPositivePrice(Decimal)
    /// Open or close outside the session's low to high range.
    case inconsistentPrices
}

/// Driven port for a ticker's daily price history (ADR-0012). `async`
/// because adapters reach the network (ADR-0003).
public protocol DailyPriceProviding: Sendable {
    /// The settled sessions from `startDate` through `endDate`, both
    /// `yyyy-MM-dd` and inclusive, in any order.
    func dailyBars(
        for ticker: Ticker,
        from startDate: String,
        through endDate: String,
    ) async throws(QuoteError) -> [DailyBar]
}
