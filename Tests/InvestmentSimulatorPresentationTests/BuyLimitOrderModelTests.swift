import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct BuyLimitOrderModelTests {
    @Test func `starts with one share, no price and nothing to place`() {
        let model = makeModel(cash: 1000)

        #expect(model.shares == 1)
        #expect(model.quoteState == .none)
        #expect(model.limitPrice == nil)
        #expect(model.cost == nil)
        #expect(!model.canGetQuote)
        #expect(!model.canPlace)
    }

    @Test func `an invalid ticker explains itself and can't be quoted`() {
        let model = makeModel(cash: 1000)

        model.tickerText = "VT I"

        #expect(model.tickerMessage == "Enter a ticker symbol, such as VTI.")
        #expect(!model.canGetQuote)
        #expect(!model.canPlace)
    }

    @Test func `a typed limit price is rounded to cents and sets the cost`() throws {
        let model = makeModel(cash: 1000)
        model.tickerText = "VTI"
        model.shares = 3
        model.enteredPrice = try #require(Decimal(string: "10.255"))

        #expect(try model.limitPrice == Money(#require(Decimal(string: "10.26"))))
        #expect(try model.cost == Money(#require(Decimal(string: "30.78"))))
        #expect(model.canPlace)
    }

    @Test(arguments: ["0", "-1", "0.004"])
    func `a limit price that rounds to zero or less can't be placed`(price: String) throws {
        let model = makeModel(cash: 1000)
        model.tickerText = "VTI"
        model.enteredPrice = try #require(Decimal(string: price))

        #expect(model.limitPrice == nil)
        #expect(model.priceMessage == "Enter a limit price above zero.")
        #expect(!model.canPlace)
    }

    @Test func `no shares can't be placed`() {
        let model = makeModel(cash: 1000)
        model.tickerText = "VTI"
        model.enteredPrice = 10
        model.shares = 0

        #expect(model.sharesMessage == "Buy at least one share.")
        #expect(model.cost == nil)
        #expect(!model.canPlace)
    }

    @Test func `an order costing more than the available cash can't be placed`() {
        let model = makeModel(cash: 25)
        model.tickerText = "VTI"
        model.enteredPrice = 10
        model.shares = 3

        #expect(model.shortfallMessage == "That costs more than the available cash.")
        #expect(!model.canPlace)
    }

    @Test func `an order can reserve all the available cash`() {
        let model = makeModel(cash: 30)
        model.tickerText = "VTI"
        model.enteredPrice = 10
        model.shares = 3

        #expect(model.shortfallMessage == nil)
        #expect(model.canPlace)
    }

    @Test func `getting a quote prefills the limit price, rounded to cents`() async throws {
        let quote = try makeQuote(price: "316.9961")
        let model = makeModel(cash: 1000, quotes: FakeQuotes(.success(quote)))
        model.tickerText = "VTI"

        await model.getQuote()

        #expect(model.quoteState == .quoted(quote))
        #expect(try model.enteredPrice == #require(Decimal(string: "317")))
    }

    @Test func `a prefilled limit price can be edited`() async throws {
        let model = try makeModel(cash: 1000, quotes: FakeQuotes(.success(makeQuote(price: "316.99"))))
        model.tickerText = "VTI"
        await model.getQuote()

        model.enteredPrice = 300

        #expect(model.limitPrice == Money(300))
    }

    @Test func `a failed quote shows its reason and keeps the typed price`() async {
        let model = makeModel(cash: 1000, quotes: FakeQuotes(.failure(.dailyLimitReached)))
        model.tickerText = "VTI"
        model.enteredPrice = 12

        await model.getQuote()

        #expect(model.quoteState == .failed(QuoteError.dailyLimitReached.localizedDescription))
        #expect(model.enteredPrice == 12)
        #expect(!model.needsAPIKey)
    }

    @Test(arguments: [QuoteError.missingAPIKey, .invalidAPIKey])
    func `a quote failing for want of an API key says so`(error: QuoteError) async {
        let model = makeModel(cash: 1000, quotes: FakeQuotes(.failure(error)))
        model.tickerText = "VTI"

        await model.getQuote()

        #expect(model.needsAPIKey)
    }

    @Test func `a quote for a ticker changed while waiting is ignored`() async throws {
        let quotes = try FakeQuotes(.success(makeQuote(price: "316.99")))
        let model = makeModel(cash: 1000, quotes: quotes)
        model.tickerText = "VTI"
        model.enteredPrice = 12
        quotes.whileAnswering { model.tickerText = "VOO" }

        await model.getQuote()

        #expect(model.quoteState == .none)
        #expect(model.enteredPrice == 12)
    }

    @Test func `changing the ticker clears the quote but keeps the price`() async throws {
        let model = try makeModel(cash: 1000, quotes: FakeQuotes(.success(makeQuote(price: "316.99"))))
        model.tickerText = "VTI"
        await model.getQuote()

        model.tickerText = "VOO"

        #expect(model.quoteState == .none)
        #expect(try model.enteredPrice == #require(Decimal(string: "316.99")))
    }

    @Test func `placing makes an order for the ticker at the time it is placed`() throws {
        var now = fixedNow
        let model = makeModel(cash: 1000, clock: { now })
        model.tickerText = "vti"
        model.shares = 4
        model.enteredPrice = 9
        now = fixedNow.addingTimeInterval(3600)

        let order = try #require(model.place())

        #expect(order.id == fixedOrderID)
        #expect(try order.ticker == Ticker("VTI"))
        #expect(order.shares == 4)
        #expect(order.limitPrice == Money(9))
        #expect(order.placedAt == now)
        #expect(order.expiresAt == LimitOrder.expiry(forPlacedAt: now))
    }

    @Test func `placing an invalid order makes nothing`() {
        #expect(makeModel(cash: 1000).place() == nil)
    }

    @Test func `expiry is shown before the order is placed`() {
        #expect(makeModel(cash: 1000).expiresAt == LimitOrder.expiry(forPlacedAt: fixedNow))
    }

    private func makeModel(
        cash: Decimal,
        quotes: FakeQuotes = FakeQuotes(.failure(.missingAPIKey)),
        clock: @escaping () -> Date = { fixedNow },
    ) -> BuyLimitOrderModel {
        BuyLimitOrderModel(availableCash: Money(cash), quotes: quotes, clock: clock, orderID: fixedOrderID)
    }
}
