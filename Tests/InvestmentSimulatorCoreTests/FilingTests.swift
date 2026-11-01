import Foundation
import InvestmentSimulatorCore
import Testing

struct FilingTests {
    private static let url = URL(string: "https://equibles.com/stocks/aapl/documents/1")!

    private func filing(
        filed: String = "2026-07-31",
        reporting: String? = nil,
        accession: String? = nil,
    ) throws -> Filing {
        try Filing(
            form: "10-Q",
            filedDate: filed,
            reportingForDate: reporting,
            accessionNumber: accession,
            url: Self.url,
        )
    }

    private func secLink(_ folder: String) -> URL? {
        URL(string: "https://www.sec.gov/Archives/edgar/data/\(folder)/")
    }

    @Test func `a filing keeps its dates`() throws {
        let filing = try filing(reporting: "2026-06-27")

        #expect(filing.filedDate == "2026-07-31")
        #expect(filing.reportingForDate == "2026-06-27")
    }

    @Test func `a filing needn't report for a date`() throws {
        #expect(try filing().reportingForDate == nil)
    }

    @Test func `a filed date must be a date`() {
        #expect(throws: FilingError.invalidDate("2026-07-31T00:00:00Z")) {
            try filing(filed: "2026-07-31T00:00:00Z")
        }
    }

    @Test func `a reporting date must be a date`() {
        #expect(throws: FilingError.invalidDate("June")) {
            try filing(reporting: "June")
        }
    }

    @Test func `a filing with an accession number links to its folder on sec.gov`() throws {
        let filing = try filing(accession: "0000320193-26-000020")

        #expect(filing.secURL(cik: 320_193) == secLink("320193/000032019326000020"))
    }

    @Test func `the sec.gov folder uses the given CIK, not the accession's prefix`() throws {
        let filing = try filing(accession: "0001193125-26-000001")

        #expect(filing.secURL(cik: 320_193) == secLink("320193/000119312526000001"))
    }

    @Test func `a filing without an accession number has no sec.gov link`() throws {
        #expect(try filing(accession: nil).secURL(cik: 320_193) == nil)
    }

    @Test func `a blank accession number has no sec.gov link`() throws {
        #expect(try filing(accession: "").secURL(cik: 320_193) == nil)
    }
}
