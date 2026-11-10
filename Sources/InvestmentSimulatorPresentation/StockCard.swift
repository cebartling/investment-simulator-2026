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

/// Where a card's Overview stands on its ticker's settled sessions of the
/// past month (PIN-510, PIN-511).
public nonisolated enum LatestSessionState: Equatable, Sendable {
    case loading
    case loaded(RecentSessions)
    /// No session in the past month, or an unknown ticker.
    case empty
    case failed(String)
}

/// A ticker's settled sessions of the past month, at least one: the latest
/// for the Overview's last session, and the rest for the change since the
/// previous close (PIN-511).
public nonisolated struct RecentSessions: Equatable, Sendable {
    /// By session date, the latest last.
    public let bars: [DailyBar]

    public var latest: DailyBar {
        bars[bars.count - 1]
    }

    /// Nil with no bars.
    public init?(_ bars: [DailyBar]) {
        guard !bars.isEmpty else {
            return nil
        }
        self.bars = bars.sorted { $0.sessionDate < $1.sessionDate }
    }
}

/// The panes of an open stock card (PIN-510).
public nonisolated enum StockPane: Hashable, CaseIterable, Sendable {
    case overview
    /// The closes, with the trades marked on them (PIN-515).
    case chart
    case purchases
    case sales
    case orders
}
