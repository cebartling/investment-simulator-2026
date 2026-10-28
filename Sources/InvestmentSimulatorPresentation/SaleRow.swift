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

/// The Sales table (PIN-409).
public extension MainWindowModel {
    /// The market sales and filled sell orders, by when they sold. A fill
    /// sold at its session's close.
    var saleRows: [SaleRow] {
        let purchases = Dictionary(uniqueKeysWithValues: experiment.purchases.map { ($0.id, $0) })
        // Experiment rejects a sale or order whose purchase it doesn't have.
        let marketRows = experiment.sales.compactMap { sale in
            purchases[sale.purchaseID].map {
                SaleRow(
                    id: sale.id,
                    kind: .market(sale.priceSource),
                    ticker: $0.ticker,
                    shares: sale.shares,
                    pricePerShare: sale.pricePerShare,
                    proceeds: sale.proceeds,
                    realizedGain: sale.realizedGain(on: $0),
                    soldAt: sale.soldAt,
                )
            }
        }
        let fillRows = experiment.limitOrders.compactMap { order -> SaleRow? in
            guard let filledOn = order.filledOn, let filledAt = order.filledAt,
                  let purchase = purchases[order.purchaseID]
            else {
                return nil
            }
            return SaleRow(
                id: order.id,
                kind: .limitFill(sessionDate: filledOn),
                ticker: purchase.ticker,
                shares: order.shares,
                pricePerShare: order.limitPrice.amount,
                proceeds: order.proceeds,
                realizedGain: order.realizedGain(on: purchase),
                soldAt: filledAt,
            )
        }
        // Sorting is stable, so sales at the same time keep their order.
        return (marketRows + fillRows).sorted { $0.soldAt < $1.soldAt }
    }
}
