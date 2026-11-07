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

    @Test func `a time is dated by its New York day wherever the user is`() throws {
        let lateInNewYork = try #require(ISO8601DateFormatter().date(from: "2026-10-20T02:00:00Z"))

        #expect(formatter.marketDay(of: lateInNewYork) == "Oct 19, 2026")
    }

    @Test(arguments: [true, false])
    func `a live-quote trade shows its day and time in the user's time zone`(delayed: Bool) {
        let text = formatter.tradeTime(of: closeTime, source: .liveQuote(delayed: delayed))

        #expect(text.hasPrefix("Oct 24, 2026"))
        #expect(text.contains("5:00"))
    }

    @Test(arguments: [
        PriceSource.close(sessionDate: "2026-10-23"),
        PriceSource.limitOrderFill(sessionDate: "2026-10-23"),
    ])
    func `a trade at a close or a fill shows only its New York session`(source: PriceSource) {
        #expect(formatter.tradeTime(of: closeTime, source: source) == "Oct 23, 2026")
    }

    @Test func `two live-quote trades on one day read differently`() {
        let earlier = formatter.tradeTime(of: closeTime, source: .liveQuote(delayed: true))
        let later = formatter.tradeTime(of: closeTime.addingTimeInterval(3600), source: .liveQuote(delayed: true))

        #expect(earlier != later)
    }

    @Test func `a live-quote sale shows when it sold in the user's time zone`() {
        let text = formatter.tradeTime(ofSaleAt: closeTime, source: .liveQuote(delayed: false))

        #expect(text.hasPrefix("Oct 24, 2026"))
        #expect(text.contains("5:00"))
    }

    @Test func `a sale at a close shows the close's session, not when it sold`() {
        let twoDaysLater = closeTime.addingTimeInterval(2 * 24 * 3600)
        let text = formatter.tradeTime(ofSaleAt: twoDaysLater, source: .close(sessionDate: "2026-10-23"))

        #expect(text == "Oct 23, 2026")
    }

    private func makeQuote(at date: Date, source: PriceSource) throws -> Quote {
        try Quote(ticker: Ticker("VTI"), price: 373.01, asOf: date, source: source)
    }
}
