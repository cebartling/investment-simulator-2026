import Foundation
import InvestmentSimulatorCore
import Testing

struct SaleTests {
    @Test func `proceeds are price times shares, rounded to cents`() throws {
        let sale = try makeSale(shares: 3, price: "316.9961")

        #expect(try sale.proceeds == Money(#require(Decimal(string: "950.99"))))
    }

    @Test func `proceeds rounding uses bankers rounding`() throws {
        let sale = try makeSale(shares: 1, price: "10.125")

        #expect(try sale.proceeds == Money(#require(Decimal(string: "10.12"))))
    }

    @Test(arguments: [0, -1])
    func `shares must be positive`(shares: Int) {
        #expect(throws: SaleError.nonPositiveShares(shares)) {
            try makeSale(shares: shares, price: "10")
        }
    }

    @Test(arguments: ["0", "-1"])
    func `price must be positive`(price: String) throws {
        let pricePerShare = try #require(Decimal(string: price))

        #expect(throws: SaleError.nonPositivePrice(pricePerShare)) {
            try makeSale(shares: 1, price: price)
        }
    }

    @Test func `realized gain is proceeds less what the sold shares cost`() throws {
        let purchase = try makePurchase(shares: 10, price: "10")
        let sale = try makeSale(shares: 4, price: "12.5")

        #expect(sale.realizedGain(on: purchase) == Money(10))
    }

    @Test func `realized gain rounds proceeds and cost before subtracting`() throws {
        // Proceeds 30.015 round to 30.02 and cost 29.985 to 29.98: 0.04, as
        // cash moved. Rounding the per-share difference times 3 gives 0.03.
        let purchase = try makePurchase(shares: 10, price: "9.995")
        let sale = try makeSale(shares: 3, price: "10.005")

        #expect(try sale.realizedGain(on: purchase) == Money(#require(Decimal(string: "0.04"))))
    }

    @Test func `a loss is a negative realized gain`() throws {
        let purchase = try makePurchase(shares: 10, price: "10")
        let sale = try makeSale(shares: 2, price: "7.5")

        #expect(sale.realizedGain(on: purchase) == Money(-5))
    }

    @Test func `a quote's live and close sources map to sale sources`() {
        #expect(SalePriceSource(.liveQuote(delayed: true)) == .liveQuote(delayed: true))
        #expect(SalePriceSource(.close(sessionDate: "2026-10-23")) == .close(sessionDate: "2026-10-23"))
    }

    @Test func `a limit fill source has no sale source`() {
        #expect(SalePriceSource(.limitOrderFill(sessionDate: "2026-10-23")) == nil)
    }
}

func makeSale(
    id: UUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!,
    purchaseID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    shares: Int,
    price: String,
    soldAt: Date = Date(timeIntervalSince1970: 1_793_000_000),
    source: SalePriceSource = .liveQuote(delayed: true),
) throws -> Sale {
    try Sale(
        id: id,
        purchaseID: purchaseID,
        shares: shares,
        pricePerShare: #require(Decimal(string: price)),
        soldAt: soldAt,
        priceSource: source,
    )
}
