import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// Where a stock card's Chart pane places its trades (PIN-515).
struct TradeMarkTests {
    private let october = "2026-10-01" ... "2026-10-31"

    @Test(arguments: ["Asia/Tokyo", "Pacific/Auckland", "America/New_York", "Pacific/Honolulu"])
    func `a trade lands on its session day in the user's time zone`(identifier: String) throws {
        let timeZone = try #require(TimeZone(identifier: identifier))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let plotted = TradeMark.plot([mark("2026-10-28", side: .sell, price: 12)], in: timeZone, within: october)

        let trade = try #require(plotted.first)
        let day = calendar.dateComponents([.year, .month, .day], from: trade.date)
        #expect(day == DateComponents(year: 2026, month: 10, day: 28))
        #expect(trade.side == .sell)
        #expect(trade.price == 12)
    }

    @Test func `only trades in the chart's sessions are placed, both ends included`() {
        let marks = [
            mark("2026-09-30", price: 1),
            mark("2026-10-01", price: 2),
            mark("2026-10-31", price: 3),
            mark("2026-11-01", price: 4),
        ]

        let plotted = TradeMark.plot(marks, in: .gmt, within: october)

        #expect(plotted.map(\.price) == [2, 3])
    }

    @Test func `a trade whose session date is not a real date is left off the chart`() {
        let marks = [mark("2026-10-32", price: 1), mark("2026-10-28", price: 2)]

        let plotted = TradeMark.plot(marks, in: .gmt, within: october)

        #expect(plotted.map(\.price) == [2])
    }

    @Test func `each placed trade keeps its own id`() {
        let marks = [mark("2026-10-28", price: 1), mark("2026-10-28", price: 1)]

        let plotted = TradeMark.plot(marks, in: .gmt, within: october)

        #expect(plotted.map(\.id) == marks.map(\.id))
    }

    private func mark(_ session: String, side: TradeMark.Side = .buy, price: Decimal) -> TradeMark {
        TradeMark(id: UUID(), side: side, sessionDate: session, price: price)
    }
}
