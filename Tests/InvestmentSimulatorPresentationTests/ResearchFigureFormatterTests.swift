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
}
