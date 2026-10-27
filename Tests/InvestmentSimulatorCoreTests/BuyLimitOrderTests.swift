import Foundation
import InvestmentSimulatorCore
import Testing

struct BuyLimitOrderTests {
    @Test func `order expires as long after it is placed as a sell order`() throws {
        let placedAt = Date(timeIntervalSince1970: 1_790_870_400)

        let order = try makeBuyLimitOrder(placedAt: placedAt)

        #expect(order.expiresAt == LimitOrder.expiry(forPlacedAt: placedAt))
    }

    @Test func `new order is open until it expires`() throws {
        let order = try makeBuyLimitOrder()

        #expect(order.filledOn == nil)
        #expect(order.cancelledAt == nil)
        #expect(order.isOpen(at: order.placedAt))
        #expect(order.isOpen(at: order.expiresAt.addingTimeInterval(-1)))
        #expect(!order.isOpen(at: order.expiresAt))
    }

    @Test(arguments: [0, -1])
    func `shares must be positive`(shares: Int) {
        #expect(throws: LimitOrderError.nonPositiveShares(shares)) {
            try makeBuyLimitOrder(shares: shares)
        }
    }

    @Test(arguments: ["0", "-1"])
    func `limit price must be positive`(price: String) throws {
        let limitPrice = try Money(#require(Decimal(string: price)))

        #expect(throws: LimitOrderError.nonPositivePrice(limitPrice)) {
            try makeBuyLimitOrder(limitPrice: price)
        }
    }

    @Test func `cost is the limit price times the shares, rounded to cents`() throws {
        let order = try makeBuyLimitOrder(shares: 3, limitPrice: "10.25")

        #expect(try order.cost == Money(#require(Decimal(string: "30.75"))))
    }

    @Test func `filled order keeps its terms and records the session`() throws {
        let order = try makeBuyLimitOrder(shares: 3, limitPrice: "10.25")

        let filled = try order.filled(on: "2026-10-23")

        #expect(filled.filledOn == "2026-10-23")
        #expect(filled.id == order.id)
        #expect(filled.ticker == order.ticker)
        #expect(filled.shares == order.shares)
        #expect(filled.limitPrice == order.limitPrice)
        #expect(filled.placedAt == order.placedAt)
        #expect(filled.expiresAt == order.expiresAt)
        #expect(!filled.isOpen(at: order.placedAt))
    }

    @Test(arguments: ["", "2026-10-2", "10/23/2026"])
    func `fill session date must be yyyy-MM-dd`(session: String) throws {
        #expect(throws: LimitOrderError.invalidSessionDate(session)) {
            try makeBuyLimitOrder().filled(on: session)
        }
    }

    @Test func `cancelled order is open until it is cancelled`() throws {
        let order = try makeBuyLimitOrder()
        let cancelledAt = order.placedAt.addingTimeInterval(3600)

        let cancelled = try order.cancelled(at: cancelledAt)

        #expect(cancelled.cancelledAt == cancelledAt)
        #expect(cancelled.isOpen(at: cancelledAt.addingTimeInterval(-1)))
        #expect(!cancelled.isOpen(at: cancelledAt))
    }

    @Test func `order can't be both filled and cancelled`() throws {
        let order = try makeBuyLimitOrder()

        #expect(throws: LimitOrderError.filledAndCancelled) {
            try order.filled(on: "2026-10-23").cancelled(at: order.placedAt)
        }
    }

    @Test func `fill purchase takes the order's id, ticker, shares and limit price`() throws {
        let order = try makeBuyLimitOrder(ticker: "AAPL", shares: 3, limitPrice: "10.25")

        let purchase = try order.purchase(filledOn: "2026-10-23")

        #expect(purchase.id == order.id)
        #expect(try purchase.ticker == Ticker("AAPL"))
        #expect(purchase.shares == 3)
        #expect(try purchase.pricePerShare == #require(Decimal(string: "10.25")))
        #expect(purchase.priceSource == .limitOrderFill(sessionDate: "2026-10-23"))
        #expect(purchase.cost == order.cost)
    }

    @Test func `fill purchase is priced at the session's 4 PM New York close`() throws {
        // 2026-10-23 is in daylight time, so 4 PM in New York is 20:00 UTC.
        let purchase = try makeBuyLimitOrder().purchase(filledOn: "2026-10-23")

        #expect(purchase.pricedAt == ISO8601DateFormatter().date(from: "2026-10-23T20:00:00Z"))
    }
}

func makeBuyLimitOrder(
    id: UUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
    ticker: String = "VTI",
    shares: Int = 1,
    limitPrice: String = "9",
    placedAt: Date = Date(timeIntervalSince1970: 1_793_000_000),
) throws -> BuyLimitOrder {
    try BuyLimitOrder.placed(
        id: id,
        ticker: Ticker(ticker),
        shares: shares,
        limitPrice: Money(#require(Decimal(string: limitPrice))),
        at: placedAt,
    )
}
