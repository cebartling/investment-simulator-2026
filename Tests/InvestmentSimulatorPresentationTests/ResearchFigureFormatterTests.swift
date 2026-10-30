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
}
