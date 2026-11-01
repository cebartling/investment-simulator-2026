import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// Starting a purchase from Research (ADR-0020).
extension MainWindowModelTests {
    @Test func `a purchase of a ticker shows the sheet filled in, and raises the window`() throws {
        let model = try makeModel(cashBalance: 500)

        try model.beginPurchase(of: Ticker("VTI"))

        #expect(model.isShowingPurchase)
        #expect(model.purchase?.tickerText == "VTI")
        #expect(model.purchase?.availableCash == Money(500))
        #expect(model.raiseCount == 1)
    }

    @Test func `a buy limit order on a ticker shows the sheet filled in, and raises the window`() throws {
        let model = try makeModel(cashBalance: 500)

        try model.beginBuyLimitOrder(of: Ticker("VTI"))

        #expect(model.isShowingBuyLimitOrder)
        #expect(model.buyLimitOrder?.tickerText == "VTI")
        #expect(model.buyLimitOrder?.availableCash == Money(500))
        #expect(model.raiseCount == 1)
    }

    @Test func `a hand-off shows the experiment section, where the sheets live`() throws {
        let model = try makeModel()
        model.selection = nil

        try model.beginPurchase(of: Ticker("VTI"))

        #expect(model.selection == .experiment)
    }

    @Test func `the toolbar's buttons don't raise the window`() throws {
        let model = try makeModel()

        model.beginPurchase()
        model.cancelPurchase()
        model.beginBuyLimitOrder()

        #expect(model.raiseCount == 0)
    }

    @Test func `a hand-off leaves a sheet being filled in alone`() throws {
        let model = try makeModel()
        model.beginPurchase()
        model.purchase?.tickerText = "BND"

        try model.beginPurchase(of: Ticker("VTI"))
        try model.beginBuyLimitOrder(of: Ticker("VTI"))

        #expect(model.purchase?.tickerText == "BND")
        #expect(!model.isShowingBuyLimitOrder)
        #expect(model.raiseCount == 0)
    }

    @Test func `no sheet is showing to begin with`() throws {
        #expect(try !makeModel().isShowingSheet)
    }

    @Test func `the new experiment sheet counts as showing`() throws {
        #expect(try makeModel(needsSetup: true).isShowingSheet)
    }

    @Test func `the buy sheets count as showing until cancelled`() throws {
        let model = try makeModel()

        model.beginPurchase()
        #expect(model.isShowingSheet)
        model.cancelPurchase()
        #expect(!model.isShowingSheet)

        model.beginBuyLimitOrder()
        #expect(model.isShowingSheet)
        model.cancelBuyLimitOrder()
        #expect(!model.isShowingSheet)
    }

    @Test func `the sell and details sheets count as showing until cancelled`() throws {
        let model = try makeModelWithPurchase()
        let purchase = try #require(model.purchases.first)

        model.beginSale(of: purchase)
        #expect(model.isShowingSheet)
        model.cancelSale()
        #expect(!model.isShowingSheet)

        model.beginLimitOrder(for: purchase)
        #expect(model.isShowingSheet)
        model.cancelLimitOrder()
        #expect(!model.isShowingSheet)

        model.beginEditingDetails()
        #expect(model.isShowingSheet)
        model.cancelEditingDetails()
        #expect(!model.isShowingSheet)
    }
}
