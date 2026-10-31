import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct ResearchFigureFormatterTests {
    private let formatter = ResearchFigureFormatter(locale: Locale(identifier: "en_US"))

    @Test func `a ratio shows two decimal places`() throws {
        #expect(try formatter.ratio(#require(Decimal(string: "39.53"))) == "39.53")
        #expect(try formatter.ratio(#require(Decimal(string: "0.5"))) == "0.50")
    }

    @Test func `a missing ratio is a dash`() {
        #expect(formatter.ratio(nil) == "—")
    }

    @Test func `a market cap is compact`() {
        #expect(formatter.marketCap(Money(5_024_265_535_488)) == "$5.02T")
        #expect(formatter.marketCap(Money(812_400_000)) == "$812.40M")
    }

    @Test func `a statement's dollars are compact, and trillions stay readable`() {
        #expect(formatter.statementFigure(.money(Money(109_417_000_000))) == "$109.42B")
        #expect(formatter.statementFigure(.money(Money(5_024_265_535_488))) == "$5.02T")
        #expect(formatter.statementFigure(.money(Money(232_000_000))) == "$232.00M")
    }

    @Test func `a statement's negative dollars keep their sign`() {
        #expect(formatter.statementFigure(.money(Money(-4_508_000_000))) == "-$4.51B")
    }

    @Test func `a statement's per-share figure is in dollars and cents`() throws {
        #expect(try formatter.statementFigure(.perShare(#require(Decimal(string: "2.03")))) == "$2.03")
    }

    @Test func `a statement's share count is compact, without a dollar sign`() {
        #expect(formatter.statementFigure(.shares(14_656_110_000)) == "14.66B")
    }

    @Test func `a figure a period lacks is a dash`() {
        #expect(formatter.statementFigure(nil) == "—")
    }

    @Test func `a quarter's label names its fiscal year`() {
        #expect(formatter.period(FiscalPeriod(year: 2026, part: .q3)) == "Q3 FY2026")
    }

    @Test func `a year's label is its fiscal year`() {
        #expect(formatter.period(FiscalPeriod(year: 2025, part: .fullYear)) == "FY2025")
    }

    @Test func `a missing market cap is a dash`() {
        #expect(formatter.marketCap(nil) == "—")
    }

    @Test func `a classification joins the sector and industry`() {
        let profile = CompanyProfile(
            name: "Apple Inc.",
            sector: "Technology",
            industry: "Consumer Electronics",
            marketCap: nil,
        )

        #expect(formatter.classification(of: profile) == "Technology · Consumer Electronics")
    }

    @Test func `a classification shows whichever part there is`() {
        let sectorOnly = CompanyProfile(name: "Apple Inc.", sector: "Technology", industry: nil, marketCap: nil)
        let industryOnly = CompanyProfile(name: "Apple Inc.", sector: nil, industry: "Software", marketCap: nil)

        #expect(formatter.classification(of: sectorOnly) == "Technology")
        #expect(formatter.classification(of: industryOnly) == "Software")
    }

    @Test func `no sector or industry is no classification`() {
        let profile = CompanyProfile(name: "Apple Inc.", sector: nil, industry: nil, marketCap: nil)

        #expect(formatter.classification(of: profile) == nil)
    }

    @Test func `a dividend keeps fractions of a cent`() throws {
        #expect(try formatter.dividendAmount(#require(Decimal(string: "0.27")), currency: "USD") == "$0.27")
        #expect(try formatter.dividendAmount(#require(Decimal(string: "0.0975")), currency: "USD") == "$0.0975")
        #expect(try formatter.dividendAmount(#require(Decimal(string: "0.82792")), currency: "USD") == "$0.82792")
        #expect(try formatter.dividendAmount(#require(Decimal(string: "0.061255")), currency: "USD") == "$0.061255")
        #expect(try formatter.dividendAmount(1, currency: "USD") == "$1.00")
    }

    @Test func `a dividend shows its own currency`() throws {
        #expect(try formatter.dividendAmount(#require(Decimal(string: "0.25")), currency: "CAD") == "CA$0.25")
    }

    @Test func `a yield is a percentage with two decimal places`() throws {
        #expect(try formatter.yield(#require(Decimal(string: "0.0397"))) == "3.97%")
        #expect(formatter.yield(0) == "0.00%")
    }

    @Test func `a missing yield is a dash`() {
        #expect(formatter.yield(nil) == "—")
    }
}
