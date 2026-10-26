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

    @Test func `sessions from the expiry date on can't fill the order`() throws {
        let experiment = try experimentWithOrder(limitPrice: "12")
        let later = Self.date("2027-02-01T15:00:00Z")

        let atExpiry = try experiment.fillingLimitOrders(from: bars(("2027-01-17", "20")), at: later)
        let beforeExpiry = try experiment.fillingLimitOrders(from: bars(("2027-01-15", "20")), at: later)

        #expect(atExpiry == experiment)
        #expect(beforeExpiry.limitOrders.map(\.filledOn) == ["2027-01-15"])
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

    private func experimentWithOrder(shares: Int = 1, limitPrice: String) throws -> Experiment {
        try Experiment(cashBalance: Money(1000))
            .purchasing(makePurchase(shares: 10, price: "10"))
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
