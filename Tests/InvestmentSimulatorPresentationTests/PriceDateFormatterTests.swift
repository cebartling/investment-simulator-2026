import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct PriceDateFormatterTests {
    /// Tokyo is ahead of New York, so a 4 PM close there is the next morning.
    let formatter = PriceDateFormatter(
        timeZone: TimeZone(identifier: "Asia/Tokyo")!,
        locale: Locale(identifier: "en_US"),
    )
    /// The Oct 23, 2026 close: 4 PM in New York.
    let closeTime = Date(timeIntervalSince1970: 1_792_785_600)

    @Test func `a close is dated by its New York session`() {
        #expect(formatter.day(of: closeTime, source: .close(sessionDate: "2026-10-23")) == "Oct 23, 2026")
    }

    @Test func `a limit order fill is dated by its New York session`() {
        #expect(formatter.day(of: closeTime, source: .limitOrderFill(sessionDate: "2026-10-23")) == "Oct 23, 2026")
    }

    @Test func `a live quote is dated in the user's time zone`() {
        #expect(formatter.day(of: closeTime, source: .liveQuote(delayed: false)) == "Oct 24, 2026")
    }

    @Test func `a close is labelled with its session`() throws {
        let quote = try makeQuote(at: closeTime, source: .close(sessionDate: "2026-10-23"))

        #expect(formatter.label(for: quote) == "Close on Oct 23, 2026")
    }

    @Test(arguments: [
        (true, "15-minute delayed quote, Oct 24, 2026"),
        (false, "Live quote, Oct 24, 2026"),
    ])
    func `a live quote is labelled with its local time`(delayed: Bool, prefix: String) throws {
        let quote = try makeQuote(at: closeTime, source: .liveQuote(delayed: delayed))

        #expect(formatter.label(for: quote).hasPrefix(prefix))
    }

    @Test func `a session is dated as itself wherever the user is`() {
        #expect(formatter.day(ofSession: "2026-10-23") == "Oct 23, 2026")
    }

    private func makeQuote(at date: Date, source: PriceSource) throws -> Quote {
        try Quote(ticker: Ticker("VTI"), price: 373.01, asOf: date, source: source)
    }
}
