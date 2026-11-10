import Foundation
import InvestmentSimulatorCore
import Testing

struct PurchaseTests {
    @Test func `cost is price times shares, rounded to cents`() throws {
        let purchase = try makePurchase(shares: 3, price: "316.9961")

        #expect(try purchase.cost == Money(#require(Decimal(string: "950.99"))))
    }

    @Test func `cost rounding uses bankers rounding`() throws {
        let purchase = try makePurchase(shares: 1, price: "10.125")

        #expect(try purchase.cost == Money(#require(Decimal(string: "10.12"))))
    }

    @Test(arguments: [0, -1])
    func `shares must be positive`(shares: Int) {
        #expect(throws: PurchaseError.nonPositiveShares(shares)) {
            try makePurchase(shares: shares, price: "10")
        }
    }

    @Test(arguments: ["0", "-1"])
    func `price must be positive`(price: String) throws {
        let pricePerShare = try #require(Decimal(string: price))

        #expect(throws: PurchaseError.nonPositivePrice(pricePerShare)) {
            try makePurchase(shares: 1, price: price)
        }
    }

    @Test func `a purchase at a live quote is in its quote's New York session`() throws {
        // 00:30 UTC on Sep 1 is 8:30 PM on Aug 31 in New York.
        let purchase = try makePurchase(shares: 1, price: "10", pricedAt: Date(timeIntervalSince1970: 1_788_222_600))

        #expect(purchase.sessionDate == "2026-08-31")
    }

    @Test(arguments: [PriceSource.close(sessionDate: "2026-10-23"), .limitOrderFill(sessionDate: "2026-10-23")])
    func `a purchase at a close or a limit fill is in that session`(source: PriceSource) throws {
        // Days after the session, so only the source can give its day.
        let purchase = try makePurchase(shares: 1, price: "10", source: source)

        #expect(purchase.sessionDate == "2026-10-23")
    }
}

func makePurchase(
    id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    ticker: String = "VTI",
    shares: Int,
    price: String,
    pricedAt: Date = Date(timeIntervalSince1970: 1_793_000_000),
    source: PriceSource = .liveQuote(delayed: true),
) throws -> Purchase {
    try Purchase(
        id: id,
        ticker: Ticker(ticker),
        shares: shares,
        pricePerShare: #require(Decimal(string: price)),
        pricedAt: pricedAt,
        priceSource: source,
    )
}
