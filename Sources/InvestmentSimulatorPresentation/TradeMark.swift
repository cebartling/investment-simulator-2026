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
