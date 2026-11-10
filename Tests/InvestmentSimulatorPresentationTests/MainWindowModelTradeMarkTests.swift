import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// The trades a stock card's Chart pane marks (PIN-515).
extension MainWindowModelTests {
    @Test func `a card marks each purchase, market sale and sell fill of its ticker in its session`() async throws {
        // 00:30 UTC on Sep 1 is 8:30 PM on Aug 31 in New York.
        let live = try makeMarkPurchase(
            id: markID(1),
            price: "10.005",
            pricedAt: Date(timeIntervalSince1970: 1_788_222_600),
            source: .liveQuote(delayed: true),
        )
        let atClose = try makeMarkPurchase(id: markID(2), price: "9", source: .close(sessionDate: "2026-10-23"))
        let otherTicker = try makeMarkPurchase(id: markID(3), ticker: "AAPL", price: "200")
        // Quoted 15 minutes before fixedNow, on 2026-10-27 in New York.
        let sale = try Sale(
            id: markID(4),
            purchaseID: live.id,
            shares: 2,
            pricePerShare: 11,
            soldAt: fixedNow,
            quotedAt: fixedNow.addingTimeInterval(-900),
            priceSource: .liveQuote(delayed: true),
        )
        let fill = try makeMarkSellOrder(id: markID(5), of: atClose, limit: 12).filled(on: "2026-10-28")
        let openSell = try makeMarkSellOrder(id: markID(6), of: live, limit: 15)
        let openBuy = try makeMarkBuyOrder(id: markID(7))
        let model = try await makeMarkModel(
            purchases: [live, atClose, otherTicker],
            sellOrders: [fill, openSell],
            buyOrders: [openBuy],
            sales: [sale],
        )

        let marks = try model.tradeMarks(of: Ticker("VTI"))

        #expect(try marks == [
            TradeMark(id: live.id, side: .buy, sessionDate: "2026-08-31", price: #require(Decimal(string: "10.005"))),
            TradeMark(id: atClose.id, side: .buy, sessionDate: "2026-10-23", price: 9),
            TradeMark(id: sale.id, side: .sell, sessionDate: "2026-10-27", price: 11),
            TradeMark(id: fill.id, side: .sell, sessionDate: "2026-10-28", price: 12),
        ])
    }

    @Test func `a card with only open orders marks nothing`() async throws {
        let model = try await makeMarkModel(buyOrders: [makeMarkBuyOrder(id: markID(1))])

        #expect(try model.tradeMarks(of: Ticker("VTI")).isEmpty)
    }

    private func markID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    private func makeMarkPurchase(
        id: UUID,
        ticker: String = "VTI",
        price: String,
        pricedAt: Date = Date(timeIntervalSince1970: 0),
        source: PriceSource = .liveQuote(delayed: false),
    ) throws -> Purchase {
        try Purchase(
            id: id,
            ticker: Ticker(ticker),
            shares: 10,
            pricePerShare: #require(Decimal(string: price)),
            pricedAt: pricedAt,
            priceSource: source,
        )
    }

    private func makeMarkSellOrder(id: UUID, of purchase: Purchase, limit: Decimal) throws -> LimitOrder {
        try LimitOrder.placed(id: id, purchaseID: purchase.id, shares: 1, limitPrice: Money(limit), at: fixedNow)
    }

    private func makeMarkBuyOrder(id: UUID) throws -> BuyLimitOrder {
        try BuyLimitOrder.placed(id: id, ticker: Ticker("VTI"), shares: 1, limitPrice: Money(8), at: fixedNow)
    }

    private func makeMarkModel(
        purchases: [Purchase] = [],
        sellOrders: [LimitOrder] = [],
        buyOrders: [BuyLimitOrder] = [],
        sales: [Sale] = [],
    ) async throws -> MainWindowModel {
        try await loadedModel(
            experiment: Experiment(
                cashBalance: Money(10000),
                purchases: purchases,
                limitOrders: sellOrders,
                buyLimitOrders: buyOrders,
                sales: sales,
            ),
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: FakeDailyPrices(),
            clock: { fixedNow },
        )
    }
}
