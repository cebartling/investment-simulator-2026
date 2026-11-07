import Foundation
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct PriceFormatterTests {
    let formatter = PriceFormatter(locale: Locale(identifier: "en_US"))

    @Test func `a price shows to the cent`() throws {
        #expect(try formatter.cents(#require(Decimal(string: "342.6138"))) == "$342.61")
        #expect(formatter.cents(1) == "$1.00")
    }

    @Test func `a price shows its own currency`() throws {
        #expect(try formatter.cents(#require(Decimal(string: "0.25")), currency: "CAD") == "CA$0.25")
    }

    @Test(arguments: [
        ("342.625", "$342.62"),
        ("342.615", "$342.62"),
        ("0.455", "$0.46"),
        ("0.445", "$0.44"),
    ])
    func `a half cent rounds to the even cent`(amount: String, expected: String) throws {
        #expect(try formatter.cents(#require(Decimal(string: amount))) == expected)
    }

    @Test func `a change shows its sign to the cent`() throws {
        #expect(try formatter.signedCents(#require(Decimal(string: "5.94"))) == "+$5.94")
        #expect(try formatter.signedCents(#require(Decimal(string: "-0.455"))) == "-$0.46")
        #expect(formatter.signedCents(0) == "$0.00")
    }

    @Test func `the full price shows the decimals rounding hid`() throws {
        #expect(try formatter.full(#require(Decimal(string: "342.6138"))) == "$342.6138")
        #expect(try formatter.full(#require(Decimal(string: "342.61383333"))) == "$342.6138")
        #expect(try formatter.full(#require(Decimal(string: "0.061255")), maxDecimals: 6) == "$0.061255")
    }

    @Test func `there's no full price when rounding hid nothing`() throws {
        #expect(try formatter.full(#require(Decimal(string: "342.61"))) == nil)
        #expect(try formatter.full(#require(Decimal(string: "342.6100"))) == nil)
        #expect(formatter.full(1) == nil)
    }
}
