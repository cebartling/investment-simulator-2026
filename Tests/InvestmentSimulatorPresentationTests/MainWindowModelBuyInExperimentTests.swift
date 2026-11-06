import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// Starting a purchase from Research (ADR-0021).
extension MainWindowModelTests {
    @Test func `a purchase of a ticker shows the sheet filled in`() async throws {
        let model = try await makeModel(cashBalance: 500)

        try model.beginPurchase(of: Ticker("VTI"))

        let purchase = try #require(model.purchase)
        #expect(model.isShowingPurchase)
        #expect(purchase.tickerText == "VTI")
        #expect(purchase.priceState == .none)
        #expect(purchase.canGetPrice)
        #expect(purchase.availableCash == Money(500))
    }

    @Test func `a buy limit order on a ticker shows the sheet filled in`() async throws {
        let model = try await makeModel(cashBalance: 500)

        try model.beginBuyLimitOrder(of: Ticker("VTI"))

        let order = try #require(model.buyLimitOrder)
        #expect(model.isShowingBuyLimitOrder)
        #expect(order.tickerText == "VTI")
        #expect(order.quoteState == .none)
        #expect(order.canGetQuote)
        #expect(order.availableCash == Money(500))
    }

    @Test func `a hand-off leaves a sheet being filled in alone`() async throws {
        let model = try await makeModel()
        model.beginPurchase()
        model.purchase?.tickerText = "BND"

        try model.beginPurchase(of: Ticker("VTI"))
        try model.beginBuyLimitOrder(of: Ticker("VTI"))

        #expect(model.purchase?.tickerText == "BND")
        #expect(!model.isShowingBuyLimitOrder)
    }

    @Test func `no sheet is showing to begin with`() async throws {
        #expect(try await !makeModel().isShowingSheet)
    }

    @Test func `the buy sheets count as showing until cancelled`() async throws {
        let model = try await makeModel()

        model.beginPurchase()
        #expect(model.isShowingSheet)
        model.cancelPurchase()
        #expect(!model.isShowingSheet)

        model.beginBuyLimitOrder()
        #expect(model.isShowingSheet)
        model.cancelBuyLimitOrder()
        #expect(!model.isShowingSheet)
    }

    @Test func `the sell and details sheets count as showing until cancelled`() async throws {
        let model = try await makeModelWithPurchase()
        let purchase = try #require(model.purchases.first)

        model.beginSale(of: purchase.ticker)
        #expect(model.isShowingSheet)
        model.cancelSale()
        #expect(!model.isShowingSheet)

        model.beginLimitOrder(of: purchase.ticker)
        #expect(model.isShowingSheet)
        model.cancelLimitOrder()
        #expect(!model.isShowingSheet)

        model.beginEditingDetails()
        #expect(model.isShowingSheet)
        model.cancelEditingDetails()
        #expect(!model.isShowingSheet)
    }
}
