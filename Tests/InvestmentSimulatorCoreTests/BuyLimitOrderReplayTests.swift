import Foundation
import InvestmentSimulatorCore
import Testing

struct BuyLimitOrderReplayTests {
    /// Noon in New York on Monday 2026-10-19. The order expires at noon on
    /// 2027-01-17.
    static let placedAt = date("2026-10-19T16:00:00Z")
    /// 10 AM in New York on Monday 2026-10-26.
    static let now = date("2026-10-26T14:00:00Z")
    static let secondOrderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!

    @Test func `no session dropping to the limit fills nothing`() throws {
        let experiment = try experimentWithOrder(limitPrice: "9")

        let replayed = try experiment.fillingLimitOrders(from: bars(("2026-10-20", "9.01")), at: Self.now)

        #expect(replayed == experiment)
    }

    @Test func `first session whose low reaches the limit fills the order into a purchase`() throws {
        let experiment = try experimentWithOrder(shares: 4, limitPrice: "9")

        let replayed = try experiment.fillingLimitOrders(
            from: bars(("2026-10-20", "9.5"), ("2026-10-21", "8.7"), ("2026-10-22", "8")),
            at: Self.now,
        )

        #expect(replayed.buyLimitOrders.map(\.filledOn) == ["2026-10-21"])
        #expect(replayed.cashBalance == experiment.cashBalance - Money(36))
        #expect(try replayed.purchases == [makeBuyOrder(shares: 4, limitPrice: "9").purchase(filledOn: "2026-10-21")])
    }

    @Test func `a low exactly at the limit fills the order`() throws {
        let experiment = try experimentWithOrder(limitPrice: "9")

        let replayed = try experiment.fillingLimitOrders(from: bars(("2026-10-20", "9")), at: Self.now)

        #expect(replayed.buyLimitOrders.map(\.filledOn) == ["2026-10-20"])
    }

    @Test func `an open below the limit still fills at the limit`() throws {
        let experiment = try experimentWithOrder(shares: 2, limitPrice: "9")
        let gapDown = try DailyBar(sessionDate: "2026-10-20", open: 7, high: 8, low: 6, close: 7)

        let replayed = try experiment.fillingLimitOrders(from: [Ticker("VTI"): [gapDown]], at: Self.now)

        #expect(replayed.cashBalance == experiment.cashBalance - Money(18))
        #expect(replayed.purchases.first?.pricePerShare == 9)
    }

    @Test func `the session the order was placed in can't fill it`() throws {
        let experiment = try experimentWithOrder(limitPrice: "9")

        let replayed = try experiment.fillingLimitOrders(
            from: bars(("2026-10-19", "1"), ("2026-10-20", "10")),
            at: Self.now,
        )

        #expect(replayed == experiment)
    }

    @Test func `today's session can't fill the order`() throws {
        let experiment = try experimentWithOrder(limitPrice: "9")

        let replayed = try experiment.fillingLimitOrders(from: bars(("2026-10-26", "1")), at: Self.now)

        #expect(replayed == experiment)
    }

    @Test func `an order that expired before the check is left alone`() throws {
        let experiment = try experimentWithOrder(limitPrice: "9")

        let replayed = try experiment.fillingLimitOrders(
            from: bars(("2027-01-15", "1")),
            at: Self.date("2027-02-01T15:00:00Z"),
        )

        #expect(replayed == experiment)
    }

    @Test func `an order cancelled before the check never fills`() throws {
        let experiment = try experimentWithOrder(limitPrice: "9")
            .cancelling(orderID: makeBuyOrder().id, at: Self.date("2026-10-23T14:00:00Z"))

        let replayed = try experiment.fillingLimitOrders(from: bars(("2026-10-20", "1")), at: Self.now)

        #expect(replayed == experiment)
        #expect(experiment.sessionsToReplay(at: Self.now).isEmpty)
    }

    @Test func `a filled buy order reopens from its file`() throws {
        let experiment = try experimentWithOrder(shares: 4, limitPrice: "9")

        let replayed = try experiment.fillingLimitOrders(from: bars(("2026-10-21", "8")), at: Self.now)

        let reopened = try Experiment(
            cashBalance: replayed.cashBalance,
            purchases: replayed.purchases,
            limitOrders: replayed.limitOrders,
            buyLimitOrders: replayed.buyLimitOrders,
        )
        #expect(reopened == replayed)
    }

    /// Only an edited file can reach this: opening it can't check what each
    /// buy order reserved (ADR-0014).
    @Test func `a buy order costing more than the opened balance fails the whole check`() throws {
        let experiment = try Experiment(
            cashBalance: Money(10),
            buyLimitOrders: [makeBuyOrder(shares: 4, limitPrice: "9")],
        )

        #expect(throws: ExperimentError.insufficientCash(cost: Money(36), available: Money(10))) {
            try experiment.fillingLimitOrders(from: bars(("2026-10-21", "8")), at: Self.now)
        }
    }

    @Test func `buy and sell orders fill in one check`() throws {
        let purchase = try makePurchase(shares: 10, price: "10")
        let sell = try makeLimitOrder(shares: 2, limitPrice: "12", placedAt: Self.placedAt)
        let experiment = try Experiment(cashBalance: Money(1000))
            .purchasing(purchase, at: Self.placedAt)
            .placing(sell)
            .placing(makeBuyOrder(shares: 4, limitPrice: "9"))
        let bar = try DailyBar(sessionDate: "2026-10-21", open: 10, high: 12.5, low: 8.5, close: 10)

        let replayed = try experiment.fillingLimitOrders(from: [Ticker("VTI"): [bar]], at: Self.now)

        #expect(replayed.limitOrders.map(\.filledOn) == ["2026-10-21"])
        #expect(replayed.buyLimitOrders.map(\.filledOn) == ["2026-10-21"])
        #expect(replayed.cashBalance == experiment.cashBalance + Money(24) - Money(36))
    }

    @Test func `sessions to replay cover an open buy order's ticker`() throws {
        let experiment = try experimentWithOrder(ticker: "AAPL", limitPrice: "9")

        #expect(try experiment.sessionsToReplay(at: Self.now) == [Ticker("AAPL"): "2026-10-19" ... "2026-10-26"])
    }

    @Test func `sessions to replay span buy and sell orders on a ticker`() throws {
        let later = Self.date("2026-10-21T16:00:00Z")
        let experiment = try Experiment(cashBalance: Money(1000))
            .purchasing(makePurchase(shares: 10, price: "10"), at: Self.placedAt)
            .placing(makeLimitOrder(limitPrice: "12", placedAt: later))
            .placing(makeBuyOrder(limitPrice: "9"))

        #expect(try experiment.sessionsToReplay(at: Self.now) == [Ticker("VTI"): "2026-10-19" ... "2026-10-26"])
    }

    @Test func `a filled buy order needs no sessions`() throws {
        let experiment = try experimentWithOrder(limitPrice: "9")
            .fillingBuyOrder(orderID: makeBuyOrder().id, on: "2026-10-20")

        #expect(experiment.sessionsToReplay(at: Self.now).isEmpty)
    }

    private func experimentWithOrder(ticker: String = "VTI", shares: Int = 1, limitPrice: String) throws -> Experiment {
        try Experiment(cashBalance: Money(1000))
            .placing(makeBuyOrder(ticker: ticker, shares: shares, limitPrice: limitPrice))
    }

    private func makeBuyOrder(
        ticker: String = "VTI",
        shares: Int = 1,
        limitPrice: String = "9",
    ) throws -> BuyLimitOrder {
        try makeBuyLimitOrder(ticker: ticker, shares: shares, limitPrice: limitPrice, placedAt: Self.placedAt)
    }

    /// VTI bars for each `(session, low)`, with the high, open and close at 20.
    private func bars(_ sessions: (String, String)...) throws -> [Ticker: [DailyBar]] {
        try [Ticker("VTI"): sessions.map { session, low in
            try makeDailyBar(session: session, open: "20", high: "20", low: low, close: "20")
        }]
    }

    private static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }
}
