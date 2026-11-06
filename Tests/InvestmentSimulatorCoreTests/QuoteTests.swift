import Foundation
import InvestmentSimulatorCore
import Testing

/// A quote's session, and its change since the previous close (PIN-511).
struct QuoteTests {
    @Test func `a live quote's session is its New York day`() throws {
        // 00:30 UTC on Sep 1 is 8:30 PM on Aug 31 in New York.
        let quote = try makeQuote(asOf: Date(timeIntervalSince1970: 1_788_222_600), source: .liveQuote(delayed: true))

        #expect(quote.sessionDate == "2026-08-31")
    }

    @Test func `a close's session is its own, whatever its time`() throws {
        // A day after the session it closed.
        let quote = try makeQuote(asOf: Self.duringNov6, source: .close(sessionDate: "2026-11-05"))

        #expect(quote.sessionDate == "2026-11-05")
    }

    @Test func `a live quote's change is from the latest close before its session`() throws {
        let quote = try makeQuote(price: "105", asOf: Self.duringNov6, source: .liveQuote(delayed: true))
        let bars = try [bar("2026-11-04", close: "80"), bar("2026-11-05", close: "100")]

        let change = try #require(quote.change(since: bars))

        #expect(change.amount == 5)
        #expect(change.percent == 5)
    }

    @Test func `a live quote's change ignores its own session's bar`() throws {
        let quote = try makeQuote(price: "105", asOf: Self.duringNov6, source: .liveQuote(delayed: true))
        let bars = try [bar("2026-11-05", close: "100"), bar("2026-11-06", close: "110")]

        #expect(try quote.change(since: bars)?.amount == 5)
    }

    @Test func `a close's change is from the session before it, in any order`() throws {
        let quote = try makeQuote(price: "100", asOf: Self.closeOfNov5, source: .close(sessionDate: "2026-11-05"))
        let bars = try [bar("2026-11-05", close: "100"), bar("2026-11-03", close: "50"), bar("2026-11-04", close: "80")]

        let change = try #require(quote.change(since: bars))

        #expect(change.amount == 20)
        #expect(change.percent == 25)
    }

    @Test func `a fall is a negative change`() throws {
        let quote = try makeQuote(price: "97.5", asOf: Self.duringNov6, source: .liveQuote(delayed: true))

        let change = try #require(quote.change(since: [bar("2026-11-05", close: "100")]))

        #expect(try change.amount == #require(Decimal(string: "-2.5")))
        #expect(try change.percent == #require(Decimal(string: "-2.5")))
    }

    @Test func `there is no change without a session before the quote's`() throws {
        let quote = try makeQuote(asOf: Self.duringNov6, source: .liveQuote(delayed: true))

        #expect(try quote.change(since: [bar("2026-11-06", close: "100")]) == nil)
        #expect(quote.change(since: []) == nil)
    }

    /// 10:42 AM on Nov 6 in New York.
    private static let duringNov6 = Date(timeIntervalSince1970: 1_793_979_720)
    /// 4 PM on Nov 5 in New York.
    private static let closeOfNov5 = Date(timeIntervalSince1970: 1_793_912_400)

    private func bar(_ session: String, close: String) throws -> DailyBar {
        try makeDailyBar(session: session, open: close, high: close, low: close, close: close)
    }

    private func makeQuote(price: String = "100", asOf: Date, source: PriceSource) throws -> Quote {
        try Quote(ticker: Ticker("VTI"), price: #require(Decimal(string: price)), asOf: asOf, source: source)
    }
}
