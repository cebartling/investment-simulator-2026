import Foundation
import InvestmentSimulatorCore

/// One stock card, as it shows collapsed (PIN-510): a ticker the experiment
/// has bought or has an order for, with what it still holds.
public nonisolated struct StockCard: Identifiable, Hashable, Sendable {
    public let ticker: Ticker
    public let heldShares: Int
    /// The price paid per share held, unrounded, or nil with none held.
    public let averagePrice: Decimal?

    public var id: Ticker {
        ticker
    }
}

/// The panes of an open stock card (PIN-510).
public enum StockPane: Hashable, CaseIterable, Sendable {
    case overview
    case purchases
    case sales
    case orders
}
