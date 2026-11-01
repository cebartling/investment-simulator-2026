import Foundation
import InvestmentSimulatorCore
import Testing

struct FilingTests {
    private static let url = URL(string: "https://equibles.com/stocks/aapl/documents/1")!

    @Test func `a filing keeps its dates`() throws {
        let filing = try Filing(form: "10-Q", filedDate: "2026-07-31", reportingForDate: "2026-06-27", accessionNumber: nil, url: Self.url)

        #expect(filing.filedDate == "2026-07-31")
        #expect(filing.reportingForDate == "2026-06-27")
    }

    @Test func `a filing needn't report for a date`() throws {
        let filing = try Filing(form: "8-K", filedDate: "2026-07-31", reportingForDate: nil, accessionNumber: nil, url: Self.url)

        #expect(filing.reportingForDate == nil)
    }

    @Test func `a filed date must be a date`() {
        #expect(throws: FilingError.invalidDate("2026-07-31T00:00:00Z")) {
            try Filing(form: "10-Q", filedDate: "2026-07-31T00:00:00Z", reportingForDate: nil, accessionNumber: nil, url: Self.url)
        }
    }

    @Test func `a reporting date must be a date`() {
        #expect(throws: FilingError.invalidDate("June")) {
            try Filing(form: "10-Q", filedDate: "2026-07-31", reportingForDate: "June", accessionNumber: nil, url: Self.url)
        }
    }

    @Test func `a filing with an accession number links to its folder on sec.gov`() throws {
        let filing = try Filing(
            form: "10-K", filedDate: "2026-07-31", reportingForDate: nil,
            accessionNumber: "0000320193-26-000020", url: Self.url,
        )

        #expect(filing.secURL(cik: 320_193) == URL(string: "https://www.sec.gov/Archives/edgar/data/320193/000032019326000020/"))
    }

    @Test func `the sec.gov folder uses the given CIK, not the accession's prefix`() throws {
        let filing = try Filing(
            form: "8-K", filedDate: "2026-07-31", reportingForDate: nil,
            accessionNumber: "0001193125-26-000001", url: Self.url,
        )

        #expect(filing.secURL(cik: 320_193) == URL(string: "https://www.sec.gov/Archives/edgar/data/320193/000119312526000001/"))
    }

    @Test func `a filing without an accession number has no sec.gov link`() throws {
        let filing = try Filing(form: "8-K", filedDate: "2026-07-31", reportingForDate: nil, accessionNumber: nil, url: Self.url)

        #expect(filing.secURL(cik: 320_193) == nil)
    }

    @Test func `a blank accession number has no sec.gov link`() throws {
        let filing = try Filing(form: "8-K", filedDate: "2026-07-31", reportingForDate: nil, accessionNumber: "", url: Self.url)

        #expect(filing.secURL(cik: 320_193) == nil)
    }
}
