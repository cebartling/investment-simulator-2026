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

/// The Limit Orders table.
public extension MainWindowModel {
    /// The buy and sell limit orders as they stand at `date`, in the order
    /// they were placed, so a view can redraw them as orders expire. Leaves
    /// out expired and cancelled orders unless
    /// `showsExpiredAndCancelledOrders` is on.
    func limitOrderRows(at date: Date) -> [LimitOrderRow] {
        let date = readingDate(date)
        let tickers = Dictionary(uniqueKeysWithValues: experiment.purchases.map { ($0.id, $0.ticker) })
        let sellRows = experiment.limitOrders.compactMap { order in
            // Experiment rejects an order whose purchase it doesn't have.
            tickers[order.purchaseID].map {
                LimitOrderRow(
                    id: order.id,
                    side: .sell,
                    ticker: $0,
                    shares: order.shares,
                    limitPrice: order.limitPrice,
                    placedAt: order.placedAt,
                    expiresAt: order.expiresAt,
                    status: status(
                        filledOn: order.filledOn,
                        cancelledAt: order.cancelledAt,
                        isOpen: order.isOpen(at: date),
                    ),
                )
            }
        }
        let buyRows = experiment.buyLimitOrders.map { order in
            LimitOrderRow(
                id: order.id,
                side: .buy,
                ticker: order.ticker,
                shares: order.shares,
                limitPrice: order.limitPrice,
                placedAt: order.placedAt,
                expiresAt: order.expiresAt,
                status: status(
                    filledOn: order.filledOn,
                    cancelledAt: order.cancelledAt,
                    isOpen: order.isOpen(at: date),
                ),
            )
        }
        // Sorting is stable, so orders placed at the same time keep their
        // order.
        return (sellRows + buyRows)
            .filter { showsExpiredAndCancelledOrders || ($0.status != .expired && $0.status != .cancelled) }
            .sorted { $0.placedAt < $1.placedAt }
    }

    private func status(filledOn: String?, cancelledAt: Date?, isOpen: Bool) -> LimitOrderRow.Status {
        if let filledOn {
            .filled(sessionDate: filledOn)
        } else if isOpen {
            .open
        } else if cancelledAt != nil {
            .cancelled
        } else {
            .expired
        }
    }
}
