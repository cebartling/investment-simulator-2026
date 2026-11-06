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

/// Where a card's Overview stands on its ticker's latest settled session
/// (PIN-510).
public nonisolated enum LatestSessionState: Equatable, Sendable {
    case loading
    case loaded(DailyBar)
    /// No session in the past month, or an unknown ticker.
    case empty
    case failed(String)
}

/// The panes of an open stock card (PIN-510).
public nonisolated enum StockPane: Hashable, CaseIterable, Sendable {
    case overview
    case purchases
    case sales
    case orders
}
