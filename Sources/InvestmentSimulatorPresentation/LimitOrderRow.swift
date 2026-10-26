import Foundation
import InvestmentSimulatorCore

/// One row of the limit orders table: the order, the ticker it sells, and
/// whether it is still open.
public nonisolated struct LimitOrderRow: Identifiable, Hashable, Sendable {
    public let order: LimitOrder
    public let ticker: Ticker
    public let isOpen: Bool

    public var id: UUID {
        order.id
    }
}
