import Foundation
import InvestmentSimulatorCore
import Testing

struct DividendHistoryTests {
    /// Noon in New York on 2026-10-30.
    private static let today = ISO8601DateFormatter().date(from: "2026-10-30T16:00:00Z")!

    /// AAPL's rows from `docs/spikes/PIN-413/equibles/dividends-AAPL.json`.
    private static let apple = [
        dividend("2026-08-10", exactly("0.27")),
        dividend("2026-05-11", exactly("0.27")),
        dividend("2026-02-09", exactly("0.26")),
        dividend("2025-11-10", exactly("0.26")),
        dividend("2025-08-11", exactly("0.26")),
        dividend("2025-05-12", exactly("0.26")),
        dividend("2025-02-10", exactly("0.25")),
        dividend("2024-11-08", exactly("0.25")),
    ]

    @Test func `the trailing amount sums the last twelve months`() {
        let history = DividendHistory(dividends: Self.apple, asOf: Self.today)

        #expect(history.trailingAmountPerShare == Self.exactly("1.06"))
    }

    @Test func `the yield divides the trailing amount by the price`() {
        let history = DividendHistory(dividends: [Self.dividend("2026-08-10", 2)], asOf: Self.today)

        #expect(history.trailingYield(atPrice: 50) == Self.exactly("0.04"))
    }

    @Test func `an ex-date a year ago today is outside the window`() {
        let history = DividendHistory(dividends: [Self.dividend("2025-10-30", 1)], asOf: Self.today)

        #expect(history.trailingAmountPerShare == 0)
    }

    @Test func `an ex-date a year ago tomorrow is inside the window`() {
        let history = DividendHistory(dividends: [Self.dividend("2025-10-31", 1)], asOf: Self.today)

        #expect(history.trailingAmountPerShare == 1)
    }

    @Test func `an ex-date today is paid and counted`() {
        let today = Self.dividend("2026-10-30", 1)

        let history = DividendHistory(dividends: [today], asOf: Self.today)

        #expect(history.paid == [today])
        #expect(history.declared.isEmpty)
        #expect(history.trailingAmountPerShare == 1)
    }

    @Test func `a future ex-date is declared and not counted`() {
        let tomorrow = Self.dividend("2026-10-31", 1)

        let history = DividendHistory(dividends: [tomorrow], asOf: Self.today)

        #expect(history.declared == [tomorrow])
        #expect(history.paid.isEmpty)
        #expect(history.trailingAmountPerShare == 0)
    }

    @Test func `today is taken in New York`() {
        // 11:30 PM on October 30 in New York is already October 31 in UTC.
        let lateEvening = ISO8601DateFormatter().date(from: "2026-10-31T03:30:00Z")!
        let tomorrow = Self.dividend("2026-10-31", 1)

        let history = DividendHistory(dividends: [tomorrow], asOf: lateEvening)

        #expect(history.declared == [tomorrow])
    }

    @Test func `both lists run newest first`() {
        let older = Self.dividend("2026-05-11", 1)
        let newer = Self.dividend("2026-08-10", 1)
        let sooner = Self.dividend("2026-11-09", 1)
        let later = Self.dividend("2027-02-08", 1)

        let history = DividendHistory(dividends: [older, sooner, newer, later], asOf: Self.today)

        #expect(history.paid == [newer, older])
        #expect(history.declared == [later, sooner])
    }

    @Test func `other currencies stay out of the sum`() {
        let history = DividendHistory(
            dividends: [Self.dividend("2026-08-10", 1), Self.dividend("2026-05-11", 5, currency: "CAD")],
            asOf: Self.today,
        )

        #expect(history.trailingAmountPerShare == 1)
        #expect(history.paid.count == 2)
    }

    @Test func `only other currencies in the window leaves no amount or yield`() {
        let history = DividendHistory(dividends: [Self.dividend("2026-08-10", 1, currency: "CAD")], asOf: Self.today)

        #expect(history.trailingAmountPerShare == nil)
        #expect(history.trailingYield(atPrice: 50) == nil)
    }

    @Test func `no ex-date in the window yields nothing, not an unknown`() {
        let history = DividendHistory(dividends: [Self.dividend("2024-11-08", 1)], asOf: Self.today)

        #expect(history.trailingYield(atPrice: 50) == 0)
    }

    @Test func `sub-cent amounts sum exactly`() {
        let history = DividendHistory(
            dividends: [
                Self.dividend("2026-08-10", Self.exactly("0.0975")),
                Self.dividend("2026-05-11", Self.exactly("0.0025")),
            ],
            asOf: Self.today,
        )

        #expect(history.trailingAmountPerShare == Self.exactly("0.1"))
    }

    @Test(arguments: [Decimal(0), Decimal(-1)])
    func `a price that isn't positive has no yield`(price: Decimal) {
        let history = DividendHistory(dividends: Self.apple, asOf: Self.today)

        #expect(history.trailingYield(atPrice: price) == nil)
    }

    private static func dividend(_ exDate: String, _ amount: Decimal, currency: String = "USD") -> Dividend {
        Dividend(exDate: exDate, amountPerShare: amount, currency: currency)
    }

    /// A `Decimal` float literal passes through `Double`; text doesn't.
    private static func exactly(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
