import Foundation
import InvestmentSimulatorCore
import Testing

struct SessionDateParserTests {
    @Test(arguments: ["Asia/Tokyo", "Pacific/Auckland", "America/New_York", "Pacific/Honolulu"])
    func `a session lands on its own day at the given hour in the parser's zone`(identifier: String) throws {
        let timeZone = try #require(TimeZone(identifier: identifier))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let date = try #require(SessionDateParser(timeZone: timeZone).date(of: "2026-10-28", hour: 12))

        #expect(calendar.dateComponents([.year, .month, .day, .hour], from: date)
            == DateComponents(year: 2026, month: 10, day: 28, hour: 12))
    }

    @Test(arguments: ["", "2026-10-2", "10/23/2026", "2026-10-23T16:00", "2026-13-01", "2026-02-30", "2026-00-10"])
    func `text that is not a real yyyy-MM-dd date gives nil`(text: String) {
        #expect(SessionDateParser(timeZone: .gmt).date(of: text, hour: 12) == nil)
    }

    @Test func `the market parser uses New York time`() throws {
        // 4 PM Eastern daylight time on 2026-06-01 is 20:00 UTC.
        let date = try #require(SessionDateParser.market.date(of: "2026-06-01", hour: 16))

        #expect(date == Date(timeIntervalSince1970: 1_780_344_000))
    }
}
