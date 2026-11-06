import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// The stock cards (PIN-510).
extension MainWindowModelTests {
    @Test func `stock cards list each ticker bought, by symbol, with held shares and average price`() async throws {
        let model = try await makeCardModel(purchases: [
            makeCardPurchase(ticker: "MSFT", shares: 2, price: "400"),
            makeCardPurchase(ticker: "AAPL", shares: 3, price: "200"),
            makeCardPurchase(ticker: "VTI", shares: 10, price: "10"),
            makeCardPurchase(ticker: "VTI", shares: 30, price: "20"),
        ])

        let cards = model.stockCards(at: fixedNow)

        #expect(cards.map(\.ticker.symbol) == ["AAPL", "MSFT", "VTI"])
        #expect(cards.map(\.heldShares) == [3, 2, 40])
        #expect(cards.map(\.averagePrice) == [200, 400, Decimal(string: "17.5")])
    }

    @Test func `a fully sold ticker keeps its card, with no shares and no average price`() async throws {
        let purchase = try makeCardPurchase(ticker: "VTI", shares: 2, price: "10")
        let sale = try Sale(
            id: UUID(),
            purchaseID: purchase.id,
            shares: 2,
            pricePerShare: 11,
            soldAt: fixedNow,
            priceSource: .liveQuote(delayed: false),
        )
        let model = try await makeCardModel(purchases: [purchase], sales: [sale])

        let cards = model.stockCards(at: fixedNow)

        #expect(cards.map(\.ticker.symbol) == ["VTI"])
        #expect(cards.first?.heldShares == 0)
        #expect(cards.first?.averagePrice == nil)
    }

    @Test func `a ticker with only an open buy order has a card`() async throws {
        let model = try await makeCardModel(buyOrders: [makeCardBuyOrder(ticker: "AAPL")])

        let cards = model.stockCards(at: fixedNow)

        #expect(cards.map(\.ticker.symbol) == ["AAPL"])
        #expect(cards.first?.heldShares == 0)
    }

    @Test func `a ticker with only expired or cancelled buy orders has a card only while they show`() async throws {
        let expired = try makeCardBuyOrder(ticker: "AAPL", placedAt: fixedNow.addingTimeInterval(-100 * 86400))
        let cancelled = try makeCardBuyOrder(ticker: "MSFT").cancelled(at: fixedNow.addingTimeInterval(-60))
        let model = try await makeCardModel(buyOrders: [expired, cancelled])

        #expect(model.stockCards(at: fixedNow).isEmpty)

        model.showsExpiredAndCancelledOrders = true

        #expect(model.stockCards(at: fixedNow).map(\.ticker.symbol) == ["AAPL", "MSFT"])
    }

    @Test func `the cards with shares held are the held tickers`() async throws {
        let sold = try makeCardPurchase(ticker: "MSFT", shares: 1, price: "400")
        let sale = try Sale(
            id: UUID(),
            purchaseID: sold.id,
            shares: 1,
            pricePerShare: 410,
            soldAt: fixedNow,
            priceSource: .liveQuote(delayed: false),
        )
        let model = try await makeCardModel(
            purchases: [makeCardPurchase(ticker: "VTI", shares: 1, price: "10"), sold],
            buyOrders: [makeCardBuyOrder(ticker: "AAPL")],
            sales: [sale],
        )

        let held = model.stockCards(at: fixedNow).filter { $0.heldShares > 0 }.map(\.ticker)

        #expect(Set(held) == model.experiment.heldTickers)
    }

    @Test func `a card starts collapsed and toggles open and closed, apart from the others`() async throws {
        let model = try await makeCardModel()
        let vti = try Ticker("VTI")
        let aapl = try Ticker("AAPL")

        #expect(model.expandedTickers.isEmpty)

        model.toggleExpansion(of: vti)
        model.toggleExpansion(of: aapl)
        #expect(model.expandedTickers == [vti, aapl])

        model.toggleExpansion(of: vti)
        #expect(model.expandedTickers == [aapl])
    }

    @Test func `each card starts on Overview and keeps its own pane`() async throws {
        let model = try await makeCardModel()
        let vti = try Ticker("VTI")
        let aapl = try Ticker("AAPL")

        model.selectPane(.sales, for: vti)

        #expect(model.selectedPane(for: vti) == .sales)
        #expect(model.selectedPane(for: aapl) == .overview)
    }

    @Test func `a card's purchases, sales and orders are its ticker's alone`() async throws {
        let vti = try makeCardPurchase(ticker: "VTI", shares: 5, price: "10")
        let aapl = try makeCardPurchase(ticker: "AAPL", shares: 5, price: "200")
        let sale = try Sale(
            id: UUID(),
            purchaseID: aapl.id,
            shares: 1,
            pricePerShare: 210,
            soldAt: fixedNow,
            priceSource: .liveQuote(delayed: false),
        )
        let sellOrder = try LimitOrder.placed(
            id: UUID(),
            purchaseID: vti.id,
            shares: 2,
            limitPrice: Money(12),
            at: fixedNow,
        )
        let buyOrder = try makeCardBuyOrder(ticker: "AAPL")
        let model = try await makeCardModel(
            purchases: [vti, aapl],
            sellOrders: [sellOrder],
            buyOrders: [buyOrder],
            sales: [sale],
        )

        #expect(try model.purchases(of: Ticker("VTI")) == [vti])
        #expect(try model.saleRows(of: Ticker("VTI")).isEmpty)
        #expect(try model.saleRows(of: Ticker("AAPL")).map(\.id) == [sale.id])
        #expect(try model.limitOrderRows(of: Ticker("VTI"), at: fixedNow).map(\.id) == [sellOrder.id])
        #expect(try model.limitOrderRows(of: Ticker("AAPL"), at: fixedNow).map(\.id) == [buyOrder.id])
    }

    private func makeCardModel(
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

    private func makeCardPurchase(ticker: String, shares: Int, price: String) throws -> Purchase {
        try Purchase(
            id: UUID(),
            ticker: Ticker(ticker),
            shares: shares,
            pricePerShare: #require(Decimal(string: price)),
            pricedAt: Date(timeIntervalSince1970: 0),
            priceSource: .liveQuote(delayed: false),
        )
    }

    private func makeCardBuyOrder(ticker: String, placedAt: Date = fixedNow) throws -> BuyLimitOrder {
        try BuyLimitOrder.placed(id: UUID(), ticker: Ticker(ticker), shares: 1, limitPrice: Money(9), at: placedAt)
    }
}
