import Foundation
import InvestmentSimulatorCore
import Testing

struct LimitOrderReplayTests {
    /// Noon in New York on Monday 2026-10-19. The order expires at noon on
    /// 2027-01-17.
    static let placedAt = date("2026-10-19T16:00:00Z")
    /// 10 AM in New York on Monday 2026-10-26.
    static let now = date("2026-10-26T14:00:00Z")
    static let secondOrderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!

    @Test func `no session reaching the limit fills nothing`() throws {
        let experiment = try experimentWithOrder(limitPrice: "12")

        let replayed = try experiment.fillingLimitOrders(from: bars(("2026-10-20", "11.99")), at: Self.now)

        #expect(replayed == experiment)
    }

    @Test func `first session whose high reaches the limit fills the order`() throws {
        let experiment = try experimentWithOrder(shares: 4, limitPrice: "12")

        let replayed = try experiment.fillingLimitOrders(
            from: bars(("2026-10-20", "11.5"), ("2026-10-21", "12.3"), ("2026-10-22", "13")),
            at: Self.now,
        )

        #expect(replayed.limitOrders.map(\.filledOn) == ["2026-10-21"])
        #expect(replayed.cashBalance == experiment.cashBalance + Money(48))
    }

    @Test func `a high exactly at the limit fills the order`() throws {
        let experiment = try experimentWithOrder(limitPrice: "12")

        let replayed = try experiment.fillingLimitOrders(from: bars(("2026-10-20", "12")), at: Self.now)

        #expect(replayed.limitOrders.map(\.filledOn) == ["2026-10-20"])
    }

    @Test func `an open above the limit still fills at the limit`() throws {
        let experiment = try experimentWithOrder(shares: 2, limitPrice: "12")
        let gapUp = try DailyBar(sessionDate: "2026-10-20", open: 15, high: 16, low: 14, close: 15)

        let replayed = try experiment.fillingLimitOrders(from: [Ticker("VTI"): [gapUp]], at: Self.now)

        #expect(replayed.cashBalance == experiment.cashBalance + Money(24))
    }

    @Test func `the session the order was placed in can't fill it`() throws {
        let experiment = try experimentWithOrder(limitPrice: "12")

        let replayed = try experiment.fillingLimitOrders(
            from: bars(("2026-10-19", "20"), ("2026-10-20", "11")),
            at: Self.now,
        )

        #expect(replayed == experiment)
    }

    @Test func `today's session can't fill the order`() throws {
        let experiment = try experimentWithOrder(limitPrice: "12")

        let replayed = try experiment.fillingLimitOrders(from: bars(("2026-10-26", "20")), at: Self.now)

        #expect(replayed == experiment)
    }

    @Test func `an order that expired before the check is left alone`() throws {
        let experiment = try experimentWithOrder(limitPrice: "12")

        let replayed = try experiment.fillingLimitOrders(
            from: bars(("2027-01-15", "20")),
            at: Self.date("2027-02-01T15:00:00Z"),
        )

        #expect(replayed == experiment)
    }

    @Test func `an order checked on its last morning fills from earlier sessions`() throws {
        let experiment = try experimentWithOrder(limitPrice: "12")
        // 10 AM in New York on 2027-01-17, two hours before the order expires.
        let lastMorning = Self.date("2027-01-17T15:00:00Z")

        let today = try experiment.fillingLimitOrders(from: bars(("2027-01-17", "20")), at: lastMorning)
        let earlier = try experiment.fillingLimitOrders(from: bars(("2027-01-15", "20")), at: lastMorning)

        #expect(today == experiment)
        #expect(earlier.limitOrders.map(\.filledOn) == ["2027-01-15"])
    }

    @Test func `shares sold again after an order expired are never sold twice`() throws {
        let expired = try makeLimitOrder(shares: 10, limitPrice: "12", placedAt: Self.date("2026-01-05T16:00:00Z"))
        let resold = try makeLimitOrder(
            id: Self.secondOrderID,
            shares: 10,
            limitPrice: "12",
            placedAt: Self.date("2026-04-10T16:00:00Z"),
        )
        let experiment = try Experiment(cashBalance: Money(1000))
            .purchasing(makePurchase(shares: 10, price: "10"), at: Self.placedAt)
            .placing(expired)
            .placing(resold)

        let replayed = try experiment.fillingLimitOrders(
            from: bars(("2026-02-10", "13"), ("2026-04-15", "13")),
            at: Self.date("2026-05-01T15:00:00Z"),
        )

        #expect(replayed.limitOrders.map(\.filledOn) == [nil, "2026-04-15"])
        #expect(replayed.cashBalance == experiment.cashBalance + Money(120))
        // A saved experiment is rebuilt this way when its file is opened.
        let reopened = try Experiment(
            cashBalance: replayed.cashBalance,
            purchases: replayed.purchases,
            limitOrders: replayed.limitOrders,
        )
        #expect(reopened == replayed)
    }

    @Test func `bars are read in session order whatever order they arrive in`() throws {
        let experiment = try experimentWithOrder(limitPrice: "12")

        let replayed = try experiment.fillingLimitOrders(
            from: bars(("2026-10-23", "13"), ("2026-10-21", "12.5"), ("2026-10-22", "14")),
            at: Self.now,
        )

        #expect(replayed.limitOrders.map(\.filledOn) == ["2026-10-21"])
    }

    @Test func `each order on a purchase fills at its own limit`() throws {
        let experiment = try experimentWithOrder(shares: 4, limitPrice: "12")
            .placing(makeLimitOrder(id: Self.secondOrderID, shares: 6, limitPrice: "13", placedAt: Self.placedAt))

        let replayed = try experiment.fillingLimitOrders(
            from: bars(("2026-10-20", "12.5"), ("2026-10-21", "13.5")),
            at: Self.now,
        )

        #expect(replayed.limitOrders.map(\.filledOn) == ["2026-10-20", "2026-10-21"])
        #expect(replayed.cashBalance == experiment.cashBalance + Money(48) + Money(78))
    }

    @Test func `an order already filled is left alone`() throws {
        let experiment = try experimentWithOrder(limitPrice: "12")
            .filling(orderID: makeLimitOrder().id, on: "2026-10-20")

        let replayed = try experiment.fillingLimitOrders(from: bars(("2026-10-21", "20")), at: Self.now)

        #expect(replayed == experiment)
    }

    @Test func `an order with no bars for its ticker is left alone`() throws {
        let experiment = try experimentWithOrder(limitPrice: "12")

        let aaplBar = try makeDailyBar(session: "2026-10-20", open: "1", high: "20", low: "1", close: "1")

        let replayed = try experiment.fillingLimitOrders(from: [Ticker("AAPL"): [aaplBar]], at: Self.now)

        #expect(replayed == experiment)
    }

    @Test func `sessions to replay run from an unfilled order's placement through today`() throws {
        let experiment = try experimentWithOrder(limitPrice: "12")

        #expect(try experiment.sessionsToReplay(at: Self.now) == [Ticker("VTI"): "2026-10-19" ... "2026-10-26"])
    }

    @Test func `an expired order needs no sessions`() throws {
        let experiment = try experimentWithOrder(limitPrice: "12")

        #expect(experiment.sessionsToReplay(at: Self.date("2027-02-01T15:00:00Z")).isEmpty)
    }

    @Test func `sessions to replay span every open order on a ticker`() throws {
        let later = Self.date("2026-10-21T16:00:00Z")
        let experiment = try experimentWithOrder(limitPrice: "12")
            .placing(makeLimitOrder(id: Self.secondOrderID, limitPrice: "13", placedAt: later))

        #expect(try experiment.sessionsToReplay(at: Self.now) == [Ticker("VTI"): "2026-10-19" ... "2026-10-26"])
    }

    @Test func `sessions to replay leave out an expired order on the same ticker`() throws {
        let later = Self.date("2026-10-21T16:00:00Z")
        let experiment = try experimentWithOrder(limitPrice: "12")
            .placing(makeLimitOrder(id: Self.secondOrderID, limitPrice: "13", placedAt: later))

        // The first order expired at noon on 2027-01-17; the second is open.
        let ranges = experiment.sessionsToReplay(at: Self.date("2027-01-19T15:00:00Z"))

        #expect(try ranges == [Ticker("VTI"): "2026-10-21" ... "2027-01-19"])
    }

    @Test func `filled orders need no sessions`() throws {
        let experiment = try experimentWithOrder(limitPrice: "12")
            .filling(orderID: makeLimitOrder().id, on: "2026-10-20")

        #expect(experiment.sessionsToReplay(at: Self.now).isEmpty)
    }

    @Test func `an order placed today needs no sessions`() throws {
        let experiment = try experimentWithOrder(limitPrice: "12")

        #expect(experiment.sessionsToReplay(at: Self.date("2026-10-19T20:00:00Z")).isEmpty)
    }

    private func experimentWithOrder(shares: Int = 1, limitPrice: String) throws -> Experiment {
        try Experiment(cashBalance: Money(1000))
            .purchasing(makePurchase(shares: 10, price: "10"), at: Self.placedAt)
            .placing(makeLimitOrder(shares: shares, limitPrice: limitPrice, placedAt: Self.placedAt))
    }

    /// VTI bars for each `(session, high)`, with the low, open and close at 1.
    private func bars(_ sessions: (String, String)...) throws -> [Ticker: [DailyBar]] {
        try [Ticker("VTI"): sessions.map { session, high in
            try makeDailyBar(session: session, open: "1", high: high, low: "1", close: "1")
        }]
    }

    private static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }
}
