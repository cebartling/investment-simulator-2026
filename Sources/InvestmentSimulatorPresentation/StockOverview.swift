import Foundation
import InvestmentSimulatorCore

/// What a stock card's Overview shows (PIN-511): the ticker's quote, its
/// change since the previous close and what the shares held are worth,
/// above the last settled session.
public nonisolated struct StockOverview: Equatable, Sendable {
    public enum Price: Equatable, Sendable {
        /// Waiting for the ticker's first quote.
        case loading
        /// The last good quote, kept through a failed refresh.
        case quoted(Quote)
        /// The first quote failed, and none has answered since.
        case failed(QuoteError)
    }

    public enum Holding: Equatable, Sendable {
        /// No shares held, so no market value or gain to show.
        case notHeld
        /// Shares held, with no quote to value them at yet.
        case unpriced
        /// The held shares at the quote, rounded to cents, and their gain
        /// against what they cost.
        case priced(marketValue: Money, gain: Gain)
    }

    public let price: Price
    /// From the latest session before the quote's. Nil without a quote,
    /// until the month's sessions load, when they fail, or when none is
    /// earlier than the quote's.
    public let change: PriceChange?
    public let holding: Holding
    /// Nil until the sessions start loading.
    public let lastSession: LatestSessionState?
}
