import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

struct ChartPointTests {
    @Test(arguments: [
        "Asia/Tokyo",
        "Pacific/Auckland",
        "Europe/London",
        "America/New_York",
        "America/Los_Angeles",
        "Pacific/Honolulu",
    ])
    func `a close lands on its session day in the user's time zone`(identifier: String) throws {
        let timeZone = try #require(TimeZone(identifier: identifier))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let points = try ChartPoint.plot([ChartPoint(bar: bar("2026-10-28", close: 100))], in: timeZone)

        let point = try #require(points.first)
        let day = calendar.dateComponents([.year, .month, .day], from: point.date)
        #expect(day == DateComponents(year: 2026, month: 10, day: 28))
        #expect(point.close == 100)
    }

    @Test func `the same points plot on the same day after the time zone changes`() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let honolulu = try #require(TimeZone(identifier: "Pacific/Honolulu"))
        let points = try [ChartPoint(bar: bar("2026-10-28", close: 100))]

        for timeZone in [tokyo, honolulu] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let plotted = try #require(ChartPoint.plot(points, in: timeZone).first)
            let day = calendar.dateComponents([.year, .month, .day], from: plotted.date)
            #expect(day == DateComponents(year: 2026, month: 10, day: 28))
        }
    }

    @Test func `a point whose session date is not a real date is left off the chart`() {
        let points = [
            ChartPoint(sessionDate: "2026-10-27", close: 99),
            ChartPoint(sessionDate: "not a date", close: 1),
            ChartPoint(sessionDate: "2026-10-28", close: 100),
        ]

        let plotted = ChartPoint.plot(points, in: .gmt)

        #expect(plotted.map(\.close) == [99, 100])
    }

    @Test(arguments: [
        ("America/New_York", "2026-03-08"),
        ("America/New_York", "2026-11-01"),
        ("Europe/London", "2026-03-29"),
        ("Pacific/Auckland", "2026-09-27"),
        ("Pacific/Auckland", "2026-04-05"),
    ])
    func `a close on a daylight saving change day stays on its day`(identifier: String, session: String) throws {
        let timeZone = try #require(TimeZone(identifier: identifier))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = session.split(separator: "-").compactMap { Int($0) }

        let points = try ChartPoint.plot([ChartPoint(bar: bar(session, close: 100))], in: timeZone)

        let point = try #require(points.first)
        let day = calendar.dateComponents([.year, .month, .day], from: point.date)
        #expect(day == DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

private func bar(_ session: String, close: Decimal) throws -> DailyBar {
    try DailyBar(sessionDate: session, open: close, high: close, low: close, close: close)
}
