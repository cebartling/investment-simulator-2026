import Foundation
import InvestmentSimulatorCore
import Testing

struct LimitOrderTests {
    @Test func `order expires 90 calendar days after it is placed`() throws {
        // Noon in New York on 2026-06-01, both dates in daylight time.
        let placedAt = Date(timeIntervalSince1970: 1_780_329_600)

        let order = try makeLimitOrder(placedAt: placedAt)

        #expect(order.expiresAt == placedAt.addingTimeInterval(90 * 86400))
    }

    @Test func `expiry keeps the time of day across a daylight saving change`() throws {
        // Noon EDT on 2026-10-01; 90 days later is noon EST on 2026-12-30.
        let placedAt = Date(timeIntervalSince1970: 1_790_870_400)

        let order = try makeLimitOrder(placedAt: placedAt)

        #expect(order.expiresAt == placedAt.addingTimeInterval(90 * 86400 + 3600))
    }

    @Test func `expiry can be shown before an order is placed`() throws {
        let placedAt = Date(timeIntervalSince1970: 1_790_870_400)

        #expect(try LimitOrder.expiry(forPlacedAt: placedAt) == makeLimitOrder(placedAt: placedAt).expiresAt)
    }

    @Test func `order is open until it expires`() throws {
        let order = try makeLimitOrder()

        #expect(order.isOpen(at: order.placedAt))
        #expect(order.isOpen(at: order.expiresAt.addingTimeInterval(-1)))
        #expect(!order.isOpen(at: order.expiresAt))
    }

    @Test(arguments: [0, -1])
    func `shares must be positive`(shares: Int) {
        #expect(throws: LimitOrderError.nonPositiveShares(shares)) {
            try makeLimitOrder(shares: shares)
        }
    }

    @Test(arguments: ["0", "-1"])
    func `limit price must be positive`(price: String) throws {
        let limitPrice = try Money(#require(Decimal(string: price)))

        #expect(throws: LimitOrderError.nonPositivePrice(limitPrice)) {
            try makeLimitOrder(limitPrice: price)
        }
    }

    @Test(arguments: [
        ("10", "316.9961", "348.7"),
        ("0", "316.9961", "317"),
        ("0", "10.25", "10.25"),
        ("12.5", "100", "112.5"),
    ])
    func `percent profit sets the limit price, rounded up to cents`(
        percent: String,
        price: String,
        expected: String,
    ) throws {
        let purchase = try makePurchase(shares: 1, price: price)

        let limitPrice = try LimitOrder.limitPrice(
            forProfitPercent: #require(Decimal(string: percent)),
            on: purchase,
        )

        #expect(try limitPrice == Money(#require(Decimal(string: expected))))
    }

    @Test func `negative percent profit is rejected`() throws {
        let purchase = try makePurchase(shares: 1, price: "10")
        let percent = try #require(Decimal(string: "-0.01"))

        #expect(throws: LimitOrderError.negativeProfitPercent(percent)) {
            try LimitOrder.limitPrice(forProfitPercent: percent, on: purchase)
        }
    }

    @Test func `new order is unfilled`() throws {
        #expect(try makeLimitOrder().filledOn == nil)
    }

    @Test func `filled order keeps its terms and records the session`() throws {
        let order = try makeLimitOrder(shares: 3, limitPrice: "348.7")

        let filled = try order.filled(on: "2026-10-23")

        #expect(filled.filledOn == "2026-10-23")
        #expect(filled.id == order.id)
        #expect(filled.purchaseID == order.purchaseID)
        #expect(filled.shares == order.shares)
        #expect(filled.limitPrice == order.limitPrice)
        #expect(filled.placedAt == order.placedAt)
        #expect(filled.expiresAt == order.expiresAt)
    }

    @Test func `filled order is no longer open`() throws {
        let filled = try makeLimitOrder().filled(on: "2026-10-23")

        #expect(!filled.isOpen(at: filled.placedAt))
    }

    @Test(arguments: ["", "2026-10-2", "10/23/2026"])
    func `fill session date must be yyyy-MM-dd`(session: String) throws {
        let order = try makeLimitOrder()

        #expect(throws: LimitOrderError.invalidSessionDate(session)) {
            try order.filled(on: session)
        }
    }

    @Test func `new order is not cancelled`() throws {
        #expect(try makeLimitOrder().cancelledAt == nil)
    }

    @Test func `cancelled order keeps its terms and records the time`() throws {
        let order = try makeLimitOrder(shares: 3, limitPrice: "348.7")
        let cancelledAt = order.placedAt.addingTimeInterval(3600)

        let cancelled = try order.cancelled(at: cancelledAt)

        #expect(cancelled.cancelledAt == cancelledAt)
        #expect(cancelled.id == order.id)
        #expect(cancelled.purchaseID == order.purchaseID)
        #expect(cancelled.shares == order.shares)
        #expect(cancelled.limitPrice == order.limitPrice)
        #expect(cancelled.placedAt == order.placedAt)
        #expect(cancelled.expiresAt == order.expiresAt)
        #expect(cancelled.filledOn == nil)
    }

    @Test func `cancelled order is open until it is cancelled`() throws {
        let order = try makeLimitOrder()
        let cancelledAt = order.placedAt.addingTimeInterval(3600)

        let cancelled = try order.cancelled(at: cancelledAt)

        #expect(cancelled.isOpen(at: order.placedAt))
        #expect(cancelled.isOpen(at: cancelledAt.addingTimeInterval(-1)))
        #expect(!cancelled.isOpen(at: cancelledAt))
    }

    @Test func `order can't be both filled and cancelled`() throws {
        let order = try makeLimitOrder()

        #expect(throws: LimitOrderError.filledAndCancelled) {
            try order.filled(on: "2026-10-23").cancelled(at: order.placedAt)
        }
        #expect(throws: LimitOrderError.filledAndCancelled) {
            try order.cancelled(at: order.placedAt).filled(on: "2026-10-23")
        }
    }

    @Test func `proceeds are the limit price times the shares`() throws {
        let order = try makeLimitOrder(shares: 3, limitPrice: "348.7")

        #expect(try order.proceeds == Money(#require(Decimal(string: "1046.10"))))
    }

    @Test func `an unfilled order has no fill time`() throws {
        #expect(try makeLimitOrder().filledAt == nil)
    }

    @Test func `a filled order dates from its session's 4 PM close in New York`() throws {
        let filled = try makeLimitOrder().filled(on: "2026-10-23")

        #expect(filled.filledAt == ISO8601DateFormatter().date(from: "2026-10-23T20:00:00Z"))
    }

    @Test func `realized gain is proceeds less what the sold shares cost`() throws {
        let purchase = try makePurchase(shares: 10, price: "9.995")
        let order = try makeLimitOrder(shares: 3, limitPrice: "12.5")

        // 37.50 − 29.98 (29.985 rounded to cents).
        #expect(try order.realizedGain(on: purchase) == Money(#require(Decimal(string: "7.52"))))
    }
}

func makeLimitOrder(
    id: UUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
    purchaseID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    shares: Int = 1,
    limitPrice: String = "12",
    placedAt: Date = Date(timeIntervalSince1970: 1_793_000_000),
) throws -> LimitOrder {
    try LimitOrder.placed(
        id: id,
        purchaseID: purchaseID,
        shares: shares,
        limitPrice: Money(#require(Decimal(string: limitPrice))),
        at: placedAt,
    )
}
