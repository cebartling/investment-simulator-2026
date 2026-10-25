import Foundation
import InvestmentSimulatorCore
import Testing

struct MoneyTests {
    @Test func `zero has a zero amount`() {
        #expect(Money.zero.amount == 0)
    }

    @Test func `amount keeps full decimal precision`() throws {
        let amount = try #require(Decimal(string: "1234.5678"))

        #expect(Money(amount).amount == amount)
    }

    @Test func `equal amounts are equal money`() throws {
        let amount = try #require(Decimal(string: "10.50"))

        #expect(Money(amount) == Money(amount))
    }

    @Test func `adding and subtracting money`() throws {
        let a = try Money(#require(Decimal(string: "100.25")))
        let b = try Money(#require(Decimal(string: "0.75")))

        #expect(a + b == Money(101))
        #expect(try a - b == Money(#require(Decimal(string: "99.5"))))
    }

    @Test func `money is ordered by amount`() {
        #expect(Money(5) < Money(10))
        #expect(!(Money(10) < Money(10)))
    }

    @Test func `multiplying a price by a share count`() throws {
        let price = try Money(#require(Decimal(string: "316.9961")))

        #expect(try price.times(3) == Money(#require(Decimal(string: "950.9883"))))
    }

    @Test(arguments: [
        ("10.004", "10"),
        ("10.005", "10"),
        ("10.015", "10.02"),
        ("10.125", "10.12"),
        ("10.135", "10.14"),
        ("10.126", "10.13"),
        ("-10.125", "-10.12"),
    ])
    func `rounding to cents uses bankers rounding`(input: String, expected: String) throws {
        let money = try Money(#require(Decimal(string: input)))

        #expect(try money.roundedToCents().amount == #require(Decimal(string: expected)))
    }
}
