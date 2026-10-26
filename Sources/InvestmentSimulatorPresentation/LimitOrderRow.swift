import Foundation
import InvestmentSimulatorCore

/// One row of the limit orders table: the order, the ticker it sells, and
/// where it stands.
public nonisolated struct LimitOrderRow: Identifiable, Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case open
        /// Filled at its limit price in the session on `yyyy-MM-dd`.
        case filled(sessionDate: String)
        case expired
    }

    public let order: LimitOrder
    public let ticker: Ticker
    public let status: Status

    public var id: UUID {
        order.id
    }
}
