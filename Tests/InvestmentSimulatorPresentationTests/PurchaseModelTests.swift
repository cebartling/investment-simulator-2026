import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct PurchaseModelTests {
    @Test func `starts with one share and no price`() {
        let model = makeModel(cash: 1000, quotes: FakeQuotes(.failure(.missingAPIKey)))

        #expect(model.shares == 1)
        #expect(model.priceState == .none)
        #expect(!model.canGetPrice)
        #expect(!model.canBuy)
        #expect(model.cost == nil)
    }

    @Test func `a valid ticker can be priced`() {
        let model = makeModel(cash: 1000, quotes: FakeQuotes(.failure(.missingAPIKey)))

        model.tickerText = "vti"

        #expect(model.canGetPrice)
        #expect(model.tickerMessage == nil)
    }

    @Test func `an invalid ticker explains itself and can't be priced`() {
        let model = makeModel(cash: 1000, quotes: FakeQuotes(.failure(.missingAPIKey)))

        model.tickerText = "VT I"

        #expect(!model.canGetPrice)
        #expect(model.tickerMessage == "Enter a ticker symbol, such as VTI.")
    }

    @Test func `getting a price shows the quote, cost and remaining cash`() async throws {
        let quote = try makeQuote(price: "250.10")
        let model = makeModel(cash: 1000, quotes: FakeQuotes(.success(quote)))
        model.tickerText = "VTI"
        model.shares = 3

        await model.getPrice()

        #expect(model.priceState == .priced(quote))
        #expect(try model.cost == Money(#require(Decimal(string: "750.30"))))
        #expect(try model.remainingCash == Money(#require(Decimal(string: "249.70"))))
        #expect(model.canBuy)
        #expect(model.shortfallMessage == nil)
    }

    @Test func `changing shares reprices without a new request`() async throws {
        let quotes = try FakeQuotes(.success(makeQuote(price: "10")))
        let model = makeModel(cash: 1000, quotes: quotes)
        model.tickerText = "VTI"
        await model.getPrice()

        model.shares = 5

        #expect(model.cost == Money(50))
        #expect(quotes.requestCount == 1)
    }

    @Test func `changing the ticker clears the price`() async throws {
        let model = try makeModel(cash: 1000, quotes: FakeQuotes(.success(makeQuote(price: "10"))))
        model.tickerText = "VTI"
        await model.getPrice()

        model.tickerText = "VOO"

        #expect(model.priceState == .none)
        #expect(!model.canBuy)
    }

    @Test func `a failed quote shows its reason`() async {
        let model = makeModel(cash: 1000, quotes: FakeQuotes(.failure(.dailyLimitReached)))
        model.tickerText = "VTI"

        await model.getPrice()

        #expect(model.priceState == .failed(QuoteError.dailyLimitReached.localizedDescription))
        #expect(!model.needsAPIKey)
        #expect(!model.canBuy)
    }

    @Test(arguments: [QuoteError.missingAPIKey, .invalidAPIKey])
    func `an API key problem points to Settings`(error: QuoteError) async {
        let model = makeModel(cash: 1000, quotes: FakeQuotes(.failure(error)))
        model.tickerText = "VTI"

        await model.getPrice()

        #expect(model.needsAPIKey)
    }

    @Test func `a purchase costing more than the cash can't be bought`() async throws {
        let model = try makeModel(cash: 100, quotes: FakeQuotes(.success(makeQuote(price: "60"))))
        model.tickerText = "VTI"
        model.shares = 2

        await model.getPrice()

        #expect(!model.canBuy)
        #expect(model.shortfallMessage == "That costs more than the cash balance.")
        #expect(model.buy() == nil)
    }

    @Test func `a purchase can spend all the cash`() async throws {
        let model = try makeModel(cash: 120, quotes: FakeQuotes(.success(makeQuote(price: "60"))))
        model.tickerText = "VTI"
        model.shares = 2

        await model.getPrice()

        #expect(model.canBuy)
        #expect(model.remainingCash == .zero)
    }

    @Test(arguments: [0, -1])
    func `shares must be at least one`(shares: Int) async throws {
        let model = try makeModel(cash: 1000, quotes: FakeQuotes(.success(makeQuote(price: "10"))))
        model.tickerText = "VTI"
        await model.getPrice()

        model.shares = shares

        #expect(!model.canBuy)
        #expect(model.cost == nil)
        #expect(model.sharesMessage == "Buy at least one share.")
    }

    @Test func `buying returns the purchase at the quoted price`() async throws {
        let quote = try makeQuote(price: "316.9961", source: .close(sessionDate: "2026-10-23"))
        let model = makeModel(cash: 1000, quotes: FakeQuotes(.success(quote)))
        model.tickerText = "vti"
        model.shares = 3
        await model.getPrice()

        let purchase = try #require(model.buy())

        #expect(try purchase == Purchase(
            id: fixedPurchaseID,
            ticker: Ticker("VTI"),
            shares: 3,
            pricePerShare: #require(Decimal(string: "316.9961")),
            pricedAt: quote.asOf,
            priceSource: .close(sessionDate: "2026-10-23"),
        ))
    }

    private func makeModel(cash: Decimal, quotes: FakeQuotes) -> PurchaseModel {
        PurchaseModel(availableCash: Money(cash), quotes: quotes, purchaseID: fixedPurchaseID)
    }
}
