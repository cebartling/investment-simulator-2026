import Foundation
import InvestmentSimulatorCore

/// One row of the limit orders table: a buy or sell order, the ticker it
/// trades, and where it stands.
public nonisolated struct LimitOrderRow: Identifiable, Hashable, Sendable {
    public enum Side: Hashable, Sendable {
        case buy
        case sell
    }

    public enum Status: Hashable, Sendable {
        case open
        /// Filled at its limit price in the session on `yyyy-MM-dd`.
        case filled(sessionDate: String)
        case expired
        case cancelled
    }

    public let id: UUID
    public let side: Side
    public let ticker: Ticker
    public let shares: Int
    public let limitPrice: Money
    public let placedAt: Date
    public let expiresAt: Date
    public let status: Status
}
