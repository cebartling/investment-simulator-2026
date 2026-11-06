import Foundation

/// A price for one share of a ticker, and where it came from.
public struct Quote: Sendable, Hashable {
    public let ticker: Ticker
    public let price: Decimal
    /// When the price was set: the trade time, or the session's close.
    public let asOf: Date
    public let source: PriceSource

    public init(ticker: Ticker, price: Decimal, asOf: Date, source: PriceSource) {
        self.ticker = ticker
        self.price = price
        self.asOf = asOf
        self.source = source
    }

    /// The session the price is from (`yyyy-MM-dd`): a close's own session,
    /// else the New York day of `asOf`. The adapter answers a stale live
    /// quote with the latest close, so a live quote is from the current
    /// session.
    public var sessionDate: String {
        switch source {
        case let .close(sessionDate), let .limitOrderFill(sessionDate):
            sessionDate
        case .liveQuote:
            InvestmentSimulatorCore.sessionDate(at: asOf)
        }
    }
}

/// Driven port for market prices (ADR-0012). `async` because adapters
/// reach the network (ADR-0003).
public protocol QuoteProviding: Sendable {
    func quote(for ticker: Ticker) async throws(QuoteError) -> Quote
}

public enum QuoteError: Error, Equatable {
    case missingAPIKey
    case invalidAPIKey
    case unknownTicker(Ticker)
    case dailyLimitReached
    /// Any other failure, with a detail for debugging.
    case unavailable(String)
}
