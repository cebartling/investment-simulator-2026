import Foundation
import InvestmentSimulatorCore

/// One row of the Sales table: a market sale or a filled sell limit order,
/// with what it made over its shares' cost (ADR-0016).
public nonisolated struct SaleRow: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Sold at a quote with this source.
        case market(SalePriceSource)
        /// A sell limit order filled in the session on `yyyy-MM-dd`.
        case limitFill(sessionDate: String)
    }

    public let id: UUID
    public let kind: Kind
    public let ticker: Ticker
    public let shares: Int
    /// As quoted, or the limit price for a fill.
    public let pricePerShare: Decimal
    public let proceeds: Money
    /// Negative for a loss.
    public let realizedGain: Money
    /// When the sale was made, or the close of a fill's session.
    public let soldAt: Date
}
