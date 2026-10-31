import Foundation
import InvestmentSimulatorCore
import Testing

struct FilingTests {
    private static let url = URL(string: "https://equibles.com/stocks/aapl/documents/1")!

    @Test func `a filing keeps its dates`() throws {
        let filing = try Filing(form: "10-Q", filedDate: "2026-07-31", reportingForDate: "2026-06-27", url: Self.url)

        #expect(filing.filedDate == "2026-07-31")
        #expect(filing.reportingForDate == "2026-06-27")
    }

    @Test func `a filing needn't report for a date`() throws {
        let filing = try Filing(form: "8-K", filedDate: "2026-07-31", reportingForDate: nil, url: Self.url)

        #expect(filing.reportingForDate == nil)
    }

    @Test func `a filed date must be a date`() {
        #expect(throws: FilingError.invalidDate("2026-07-31T00:00:00Z")) {
            try Filing(form: "10-Q", filedDate: "2026-07-31T00:00:00Z", reportingForDate: nil, url: Self.url)
        }
    }

    @Test func `a reporting date must be a date`() {
        #expect(throws: FilingError.invalidDate("June")) {
            try Filing(form: "10-Q", filedDate: "2026-07-31", reportingForDate: "June", url: Self.url)
        }
    }
}
