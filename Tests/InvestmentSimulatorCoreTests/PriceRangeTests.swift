import Foundation
import InvestmentSimulatorCore
import Testing

struct PriceRangeTests {
    @Test(arguments: [
        (PriceRange.oneMonth, "2026-09-29"),
        (.sixMonths, "2026-04-29"),
        (.oneYear, "2025-10-29"),
        (.fiveYears, "2021-10-29"),
    ])
    func `a range reaches back from today in New York`(range: PriceRange, start: String) {
        #expect(range.sessions(endingAt: instant("2026-10-29T18:00:00Z")) == start ... "2026-10-29")
    }

    @Test func `late evening in New York is still that day`() {
        // 11:30 PM on October 29 in New York is already October 30 in UTC.
        let sessions = PriceRange.oneMonth.sessions(endingAt: instant("2026-10-30T03:30:00Z"))

        #expect(sessions == "2026-09-29" ... "2026-10-29")
    }

    @Test func `a month back from a long month's end is the shorter month's end`() {
        let sessions = PriceRange.oneMonth.sessions(endingAt: instant("2026-03-31T16:00:00Z"))

        #expect(sessions == "2026-02-28" ... "2026-03-31")
    }

    @Test func `only five years uses weekly bars`() {
        #expect(PriceRange.allCases.map(\.interval) == [.daily, .daily, .daily, .weekly])
    }

    private func instant(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }
}
