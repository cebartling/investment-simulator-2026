import Foundation
import InvestmentSimulatorCore

/// A trade marked on a stock card's Chart pane (PIN-515): a purchase, a
/// market sale or a filled sell order, at the session and price it was made
/// at. Equibles has only daily bars, so a trade is placed by its day alone.
public nonisolated struct TradeMark: Identifiable, Equatable, Sendable {
    public enum Side: Equatable, Sendable {
        case buy
        case sell
    }

    /// The purchase's, sale's or order's own.
    public let id: UUID
    public let side: Side
    /// The New York session the trade was priced in (`yyyy-MM-dd`).
    public let sessionDate: String
    /// As quoted, which can include fractions of a cent, or the limit price
    /// for a fill.
    public let price: Decimal

    public init(id: UUID, side: Side, sessionDate: String, price: Decimal) {
        self.id = id
        self.side = side
        self.sessionDate = sessionDate
        self.price = price
    }

    /// A trade at its place on a chart axis.
    public struct Plotted: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let side: Side
        public let date: Date
        public let price: Decimal
    }

    /// Places each trade in `sessions`, the chart's range, at noon of its
    /// session's day in `timeZone`, as `ChartPoint.plot(_:in:)` places a
    /// close, so a trade sits on its session's point. A trade outside the
    /// range is left out rather than stretching the axis to it, and so is
    /// one whose session date isn't a real date.
    public static func plot(
        _ marks: [TradeMark],
        in timeZone: TimeZone,
        within sessions: ClosedRange<String>,
    ) -> [Plotted] {
        let parser = SessionDateParser(timeZone: timeZone)
        return marks.compactMap { mark in
            guard sessions.contains(mark.sessionDate) else {
                return nil
            }
            return parser.date(of: mark.sessionDate, hour: 12).map {
                Plotted(id: mark.id, side: mark.side, date: $0, price: mark.price)
            }
        }
    }
}

/// The trades of a stock card's Chart pane (PIN-515).
public extension MainWindowModel {
    /// The trades of `ticker`: each purchase, including buy limit fills and
    /// purchases sold since, then each market sale, then each filled sell
    /// order. An order that hasn't filled isn't a trade, so it isn't marked.
    func tradeMarks(of ticker: Ticker) -> [TradeMark] {
        let purchases = purchases(of: ticker)
        let purchaseIDs = Set(purchases.map(\.id))
        let buys = purchases.map {
            TradeMark(id: $0.id, side: .buy, sessionDate: $0.sessionDate, price: $0.pricePerShare)
        }
        let sales = experiment.sales.filter { purchaseIDs.contains($0.purchaseID) }.map {
            TradeMark(id: $0.id, side: .sell, sessionDate: $0.sessionDate, price: $0.pricePerShare)
        }
        let fills = experiment.limitOrders.compactMap { order -> TradeMark? in
            guard purchaseIDs.contains(order.purchaseID), let filledOn = order.filledOn else {
                return nil
            }
            return TradeMark(id: order.id, side: .sell, sessionDate: filledOn, price: order.limitPrice.amount)
        }
        return buys + sales + fills
    }
}
