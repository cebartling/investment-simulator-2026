import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// Choosing the purchase a sell sheet sells from (PIN-510).
extension MainWindowModelTests {
    @Test func `a sale of a ticker offers its held purchases, starting on the one asked for`() async throws {
        let model = try await makeModelWithChoices()

        try model.beginSale(of: Ticker("VTI"), selecting: SellChoiceIDs.second)

        // The sold-out purchase and the AAPL one aren't offered.
        #expect(model.sale?.choices.map(\.purchase.id) == [fixedPurchaseID, SellChoiceIDs.second])
        #expect(model.sale?.choices.map(\.availableShares) == [6, 5])
        #expect(model.sale?.purchase.id == SellChoiceIDs.second)
        #expect(model.isShowingSale)
    }

    @Test func `a sell limit order of a ticker offers its held purchases, starting on one asked for`() async throws {
        let model = try await makeModelWithChoices()

        try model.beginLimitOrder(of: Ticker("VTI"), selecting: SellChoiceIDs.second)

        #expect(model.limitOrder?.choices.map(\.purchase.id) == [fixedPurchaseID, SellChoiceIDs.second])
        #expect(model.limitOrder?.choices.map(\.availableShares) == [6, 5])
        #expect(model.limitOrder?.purchase.id == SellChoiceIDs.second)
        #expect(model.isShowingLimitOrder)
    }

    @Test func `a ticker with no shares held can't begin a sale or a sell limit order`() async throws {
        let model = try await makeModelWithChoices()

        try model.beginSale(of: Ticker("MSFT"))
        try model.beginLimitOrder(of: Ticker("MSFT"))

        #expect(model.sale == nil)
        #expect(!model.isShowingSale)
        #expect(model.limitOrder == nil)
        #expect(!model.isShowingLimitOrder)
    }

    @Test func `asking for a purchase that isn't offered starts on the first with free shares`() async throws {
        let model = try await makeModelWithChoices()

        try model.beginSale(of: Ticker("VTI"), selecting: SellChoiceIDs.soldOut)
        try model.beginLimitOrder(of: Ticker("VTI"), selecting: SellChoiceIDs.soldOut)

        #expect(model.sale?.purchase.id == fixedPurchaseID)
        #expect(model.limitOrder?.purchase.id == fixedPurchaseID)
    }

    @Test func `a fully sold ticker can't begin a sale or a sell limit order`() async throws {
        let purchase = try makePurchase(id: SellChoiceIDs.aapl, ticker: "AAPL", shares: 3)
        let sale = try Sale(
            id: SellChoiceIDs.sale,
            purchaseID: purchase.id,
            shares: 3,
            pricePerShare: 11,
            soldAt: Date(timeIntervalSince1970: 1),
            priceSource: .liveQuote(delayed: false),
        )
        let model = try await loadedModel(
            experiment: Experiment(cashBalance: Money(100), purchases: [purchase], sales: [sale]),
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: FakeDailyPrices(),
            clock: { fixedNow },
        )

        try model.beginSale(of: Ticker("AAPL"), selecting: purchase.id)
        try model.beginLimitOrder(of: Ticker("AAPL"), selecting: purchase.id)

        #expect(model.sale == nil)
        #expect(!model.isShowingSale)
        #expect(model.limitOrder == nil)
        #expect(!model.isShowingLimitOrder)
    }

    /// VTI bought three times, one purchase sold out and another with 4 of
    /// its 10 shares in an open order, and AAPL bought once.
    private func makeModelWithChoices() async throws -> MainWindowModel {
        let purchases = try [
            makePurchase(id: fixedPurchaseID, ticker: "VTI", shares: 10),
            makePurchase(id: SellChoiceIDs.soldOut, ticker: "VTI", shares: 2),
            makePurchase(id: SellChoiceIDs.aapl, ticker: "AAPL", shares: 3),
            makePurchase(id: SellChoiceIDs.second, ticker: "VTI", shares: 5),
        ]
        let sale = try Sale(
            id: SellChoiceIDs.sale,
            purchaseID: SellChoiceIDs.soldOut,
            shares: 2,
            pricePerShare: 11,
            soldAt: Date(timeIntervalSince1970: 1),
            priceSource: .liveQuote(delayed: false),
        )
        return try await loadedModel(
            experiment: Experiment(
                cashBalance: Money(100),
                purchases: purchases,
                limitOrders: [makeOrder(shares: 4)],
                sales: [sale],
            ),
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: FakeDailyPrices(),
            clock: { fixedNow },
        )
    }

    private func makePurchase(id: UUID, ticker: String, shares: Int) throws -> Purchase {
        try Purchase(
            id: id,
            ticker: Ticker(ticker),
            shares: shares,
            pricePerShare: 10,
            pricedAt: Date(timeIntervalSince1970: 0),
            priceSource: .liveQuote(delayed: false),
        )
    }
}

private enum SellChoiceIDs {
    static let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let soldOut = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let aapl = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    static let sale = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
}
