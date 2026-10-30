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

/// How much time one bar covers.
public enum BarInterval: Sendable {
    case daily
    /// A week's bar is dated by its last session, so it reads as a
    /// `DailyBar`. The current week's bar can still be changing.
    case weekly
}

/// Driven port for a ticker's daily price history (ADR-0012), which can
/// also come rolled up into weekly bars (ADR-0019). `async` because
/// adapters reach the network (ADR-0003).
public protocol DailyPriceProviding: Sendable {
    /// The bars from `startDate` through `endDate`, both `yyyy-MM-dd` and
    /// inclusive, in any order. Daily bars are settled sessions.
    func dailyBars(
        for ticker: Ticker,
        from startDate: String,
        through endDate: String,
        interval: BarInterval,
    ) async throws(QuoteError) -> [DailyBar]
}

public extension DailyPriceProviding {
    /// The settled daily bars from `startDate` through `endDate`.
    func dailyBars(
        for ticker: Ticker,
        from startDate: String,
        through endDate: String,
    ) async throws(QuoteError) -> [DailyBar] {
        try await dailyBars(for: ticker, from: startDate, through: endDate, interval: .daily)
    }
}
