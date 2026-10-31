import Foundation
import InvestmentSimulatorCore
import Testing

struct DividendHistoryTests {
    /// Noon in New York on 2026-10-30.
    private static let today = ISO8601DateFormatter().date(from: "2026-10-30T16:00:00Z")!

    /// AAPL's rows from `docs/spikes/PIN-413/equibles/dividends-AAPL.json`.
    private static func apple() throws -> [Dividend] {
        try [
            dividend("2026-08-10", exactly("0.27")),
            dividend("2026-05-11", exactly("0.27")),
            dividend("2026-02-09", exactly("0.26")),
            dividend("2025-11-10", exactly("0.26")),
            dividend("2025-08-11", exactly("0.26")),
            dividend("2025-05-12", exactly("0.26")),
            dividend("2025-02-10", exactly("0.25")),
            dividend("2024-11-08", exactly("0.25")),
        ]
    }

    @Test func `the trailing amount sums the last twelve months`() throws {
        let history = try DividendHistory(dividends: Self.apple(), asOf: Self.today)

        #expect(history.trailingAmountPerShare == Self.exactly("1.06"))
    }

    @Test func `the yield divides the trailing amount by the price`() throws {
        let history = try DividendHistory(dividends: [Self.dividend("2026-08-10", 2)], asOf: Self.today)

        #expect(history.trailingYield(atPrice: 50) == Self.exactly("0.04"))
    }

    @Test func `an ex-date a year ago today is outside the window`() throws {
        let history = try DividendHistory(dividends: [Self.dividend("2025-10-30", 1)], asOf: Self.today)

        #expect(history.trailingAmountPerShare == 0)
    }

    @Test func `an ex-date a year ago tomorrow is inside the window`() throws {
        let history = try DividendHistory(dividends: [Self.dividend("2025-10-31", 1)], asOf: Self.today)

        #expect(history.trailingAmountPerShare == 1)
    }

    @Test func `an ex-date today is paid and counted`() throws {
        let today = try Self.dividend("2026-10-30", 1)

        let history = try DividendHistory(dividends: [today], asOf: Self.today)

        #expect(history.paid == [today])
        #expect(history.declared.isEmpty)
        #expect(history.trailingAmountPerShare == 1)
    }

    @Test func `a future ex-date is declared and not counted`() throws {
        let tomorrow = try Self.dividend("2026-10-31", 1)

        let history = try DividendHistory(dividends: [tomorrow], asOf: Self.today)

        #expect(history.declared == [tomorrow])
        #expect(history.paid.isEmpty)
        #expect(history.trailingAmountPerShare == 0)
    }

    @Test func `today is taken in New York`() throws {
        // 11:30 PM on October 30 in New York is already October 31 in UTC.
        let lateEvening = try #require(ISO8601DateFormatter().date(from: "2026-10-31T03:30:00Z"))
        let tomorrow = try Self.dividend("2026-10-31", 1)

        let history = try DividendHistory(dividends: [tomorrow], asOf: lateEvening)

        #expect(history.declared == [tomorrow])
    }

    @Test func `both lists run newest first`() throws {
        let older = try Self.dividend("2026-05-11", 1)
        let newer = try Self.dividend("2026-08-10", 1)
        let sooner = try Self.dividend("2026-11-09", 1)
        let later = try Self.dividend("2027-02-08", 1)

        let history = try DividendHistory(dividends: [older, sooner, newer, later], asOf: Self.today)

        #expect(history.paid == [newer, older])
        #expect(history.declared == [later, sooner])
    }

    @Test func `other currencies stay out of the sum`() throws {
        let history = try DividendHistory(
            dividends: [Self.dividend("2026-08-10", 1), Self.dividend("2026-05-11", 5, currency: "CAD")],
            asOf: Self.today,
        )

        #expect(history.trailingAmountPerShare == 1)
        #expect(history.paid.count == 2)
    }

    @Test func `only other currencies in the window leaves no amount or yield`() throws {
        let canadian = try Self.dividend("2026-08-10", 1, currency: "CAD")

        let history = DividendHistory(dividends: [canadian], asOf: Self.today)

        #expect(history.trailingAmountPerShare == nil)
        #expect(history.trailingYield(atPrice: 50) == nil)
    }

    @Test func `no ex-date in the window yields nothing, not an unknown`() throws {
        let history = try DividendHistory(dividends: [Self.dividend("2024-11-08", 1)], asOf: Self.today)

        #expect(history.trailingYield(atPrice: 50) == 0)
    }

    @Test func `sub-cent amounts sum exactly`() throws {
        let history = try DividendHistory(
            dividends: [
                Self.dividend("2026-08-10", Self.exactly("0.0975")),
                Self.dividend("2026-05-11", Self.exactly("0.0025")),
            ],
            asOf: Self.today,
        )

        #expect(history.trailingAmountPerShare == Self.exactly("0.1"))
    }

    @Test(arguments: ["", "10/23/2026", "2026-08-10T00:00:00Z"])
    func `an ex-date must be yyyy-MM-dd`(exDate: String) {
        #expect(throws: DividendError.invalidExDate(exDate)) {
            try Dividend(exDate: exDate, amountPerShare: 1, currency: "USD")
        }
    }

    @Test(arguments: [Decimal(0), Decimal(-1)])
    func `a price that isn't positive has no yield`(price: Decimal) throws {
        let history = try DividendHistory(dividends: Self.apple(), asOf: Self.today)

        #expect(history.trailingYield(atPrice: price) == nil)
    }

    private static func dividend(
        _ exDate: String,
        _ amount: Decimal,
        currency: String = "USD",
    ) throws -> Dividend {
        try Dividend(exDate: exDate, amountPerShare: amount, currency: currency)
    }

    /// A `Decimal` float literal passes through `Double`; text doesn't.
    private static func exactly(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
