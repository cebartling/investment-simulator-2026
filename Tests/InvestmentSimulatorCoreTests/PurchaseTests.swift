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
}

func makePurchase(
    id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    ticker: String = "VTI",
    shares: Int,
    price: String,
    source: PriceSource = .liveQuote(delayed: true),
) throws -> Purchase {
    try Purchase(
        id: id,
        ticker: Ticker(ticker),
        shares: shares,
        pricePerShare: #require(Decimal(string: price)),
        pricedAt: Date(timeIntervalSince1970: 1_793_000_000),
        priceSource: source,
    )
}
