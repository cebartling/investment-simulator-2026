import Foundation
import InvestmentSimulatorCore
import Testing

/// A ticker's held shares and average price, for its stock card (PIN-510).
struct StockPositionTests {
    @Test func `held shares of a ticker add up its purchases and no other ticker's`() throws {
        let experiment = try Experiment(cashBalance: Money(1000))
            .purchasing(makePurchase(ticker: "VTI", shares: 3, price: "10"), at: Self.now)
            .purchasing(makePurchase(id: Self.secondPurchaseID, ticker: "AAPL", shares: 5, price: "10"), at: Self.now)
            .purchasing(makePurchase(id: Self.thirdPurchaseID, ticker: "VTI", shares: 4, price: "10"), at: Self.now)

        #expect(try experiment.heldShares(of: Ticker("VTI")) == 7)
        #expect(try experiment.heldShares(of: Ticker("AAPL")) == 5)
    }

    @Test func `held shares of a ticker leave out sales and filled sells but not open orders`() throws {
        let filled = try makeLimitOrder(shares: 2)
        let open = try makeLimitOrder(id: Self.secondSellID, shares: 3)
        let experiment = try experimentWithPurchase(shares: 10)
            .selling(makeSale(shares: 1, price: "11"))
            .placing(filled)
            .placing(open)
            .filling(orderID: filled.id, on: "2026-10-23")

        #expect(try experiment.heldShares(of: Ticker("VTI")) == 7)
    }

    @Test func `a ticker with no purchases has no held shares and no average price`() throws {
        let experiment = try experimentWithPurchase(shares: 10)

        #expect(try experiment.heldShares(of: Ticker("AAPL")) == 0)
        #expect(try experiment.averagePrice(of: Ticker("AAPL")) == nil)
    }

    @Test func `average price of one purchase is its price exactly`() throws {
        // Its cost rounds to 950.99, which over 3 shares would be 316.9966….
        let experiment = try Experiment(cashBalance: Money(1000))
            .purchasing(makePurchase(shares: 3, price: "316.9961"), at: Self.now)

        #expect(try experiment.averagePrice(of: Ticker("VTI")) == Decimal(string: "316.9961"))
    }

    @Test func `average price weighs each purchase by its held shares`() throws {
        let experiment = try Experiment(cashBalance: Money(2000))
            .purchasing(makePurchase(ticker: "VTI", shares: 10, price: "10"), at: Self.now)
            .purchasing(makePurchase(id: Self.secondPurchaseID, ticker: "VTI", shares: 30, price: "20"), at: Self.now)
            .purchasing(makePurchase(id: Self.thirdPurchaseID, ticker: "AAPL", shares: 1, price: "500"), at: Self.now)

        #expect(try experiment.averagePrice(of: Ticker("VTI")) == Decimal(string: "17.5"))
    }

    @Test func `average price counts only the shares still held`() throws {
        let experiment = try Experiment(cashBalance: Money(1000))
            .purchasing(makePurchase(shares: 10, price: "10"), at: Self.now)
            .purchasing(makePurchase(id: Self.secondPurchaseID, shares: 5, price: "20"), at: Self.now)
            .selling(makeSale(shares: 5, price: "12"))

        // 5 × 10 + 5 × 20 over 10 shares.
        #expect(try experiment.averagePrice(of: Ticker("VTI")) == 15)
    }

    @Test func `a fully sold ticker has no held shares and no average price`() throws {
        let experiment = try experimentWithPurchase(shares: 10)
            .selling(makeSale(shares: 10, price: "12"))

        #expect(try experiment.heldShares(of: Ticker("VTI")) == 0)
        #expect(try experiment.averagePrice(of: Ticker("VTI")) == nil)
    }

    private static let now = Date(timeIntervalSince1970: 1_793_000_000)
    private static let secondPurchaseID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let thirdPurchaseID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private static let secondSellID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!

    private func experimentWithPurchase(shares: Int) throws -> Experiment {
        try Experiment(cashBalance: Money(1000)).purchasing(makePurchase(shares: shares, price: "10"), at: Self.now)
    }
}
