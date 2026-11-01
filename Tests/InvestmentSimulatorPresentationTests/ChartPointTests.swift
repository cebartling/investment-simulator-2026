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

        let point = try ChartPoint(bar: bar("2026-10-28", close: 100), timeZone: timeZone)

        let day = calendar.dateComponents([.year, .month, .day], from: point.date)
        #expect(day == DateComponents(year: 2026, month: 10, day: 28))
        #expect(point.close == 100)
    }
}

private func bar(_ session: String, close: Decimal) throws -> DailyBar {
    try DailyBar(sessionDate: session, open: close, high: close, low: close, close: close)
}
