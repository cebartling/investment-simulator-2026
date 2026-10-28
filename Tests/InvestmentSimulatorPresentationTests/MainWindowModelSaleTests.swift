import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// Market sales and the Sales table (PIN-409).
extension MainWindowModelTests {
    @Test func `beginning a sale shows the sheet with the purchase's free shares and the cash`() throws {
        let model = try makeModelForSale(orders: [makeOrder(shares: 4)])

        try model.beginSale(of: #require(model.purchases.first))

        #expect(model.isShowingSale)
        #expect(model.sale?.purchase.id == fixedPurchaseID)
        #expect(model.sale?.availableShares == 6)
        #expect(model.sale?.cashBalance == Money(100))
    }

    @Test func `completing a sale credits the proceeds, records it, hides the sheet and celebrates`() async throws {
        let model = try makeModelForSale(quotes: FakeQuotes(.success(makeQuote(price: "12.5"))))
        try model.beginSale(of: #require(model.purchases.first))
        model.sale?.shares = 4
        await model.sale?.getPrice()

        let updated = try #require(model.completeSale())

        #expect(updated.cashBalance == Money(150))
        #expect(updated.sales.map(\.shares) == [4])
        #expect(updated.sales.first?.soldAt == fixedNow)
        #expect(model.experiment == updated)
        #expect(!model.isShowingSale)
        #expect(model.sale == nil)
        #expect(model.celebrationCount == 1)
    }

    @Test func `a sale that can't be made leaves the sheet open and doesn't celebrate`() throws {
        let model = try makeModelForSale()
        try model.beginSale(of: #require(model.purchases.first))

        #expect(model.completeSale() == nil)
        #expect(model.isShowingSale)
        #expect(model.celebrationCount == 0)
    }

    @Test func `cancelling a sale hides the sheet and changes nothing`() throws {
        let model = try makeModelForSale()
        let before = model.experiment
        try model.beginSale(of: #require(model.purchases.first))

        model.cancelSale()

        #expect(!model.isShowingSale)
        #expect(model.sale == nil)
        #expect(model.experiment == before)
    }

    @Test func `sale rows list market sales and filled sell orders by date, with their gains`() throws {
        let market = try Sale(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")),
            purchaseID: fixedPurchaseID,
            shares: 2,
            pricePerShare: #require(Decimal(string: "11.005")),
            soldAt: threeDaysLater,
            priceSource: .liveQuote(delayed: true),
        )
        let open = try makeOrder(id: #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")), shares: 1)
        let filled = try makeOrder(shares: 4).filled(on: "2026-10-28")
        let model = try makeModelForSale(orders: [filled, open], sales: [market])

        let rows = model.saleRows

        // The fill dates from 2026-10-28's close, before the market sale.
        #expect(rows.map(\.id) == [filled.id, market.id])
        #expect(rows[0].kind == .limitFill(sessionDate: "2026-10-28"))
        #expect(try rows[0].ticker == Ticker("VTI"))
        #expect(rows[0].shares == 4)
        #expect(rows[0].pricePerShare == 12)
        #expect(rows[0].proceeds == Money(48))
        #expect(rows[0].realizedGain == Money(8))
        #expect(rows[0].soldAt == filled.filledAt)
        #expect(rows[1].kind == .market(.liveQuote(delayed: true)))
        // 22.01 (22.010) less 20.
        #expect(try rows[1].realizedGain == Money(#require(Decimal(string: "2.01"))))
        #expect(rows[1].soldAt == threeDaysLater)
    }

    @Test func `an experiment with no sales or fills has no sale rows`() throws {
        #expect(try makeModelForSale(orders: [makeOrder(shares: 4)]).saleRows.isEmpty)
    }

    private func makeModelForSale(
        orders: [LimitOrder] = [],
        sales: [Sale] = [],
        quotes: FakeQuotes = FakeQuotes(.failure(.missingAPIKey)),
    ) throws -> MainWindowModel {
        let purchase = try Purchase(
            id: fixedPurchaseID,
            ticker: Ticker("VTI"),
            shares: 10,
            pricePerShare: 10,
            pricedAt: Date(timeIntervalSince1970: 0),
            priceSource: .liveQuote(delayed: false),
        )
        return try MainWindowModel(
            experiment: Experiment(cashBalance: Money(100), purchases: [purchase], limitOrders: orders, sales: sales),
            needsSetup: false,
            quotes: quotes,
            dailyPrices: FakeDailyPrices(),
            clock: { fixedNow },
        )
    }
}
