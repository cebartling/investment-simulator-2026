import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// The Market Sell sheet (PIN-409).
@MainActor
struct SaleModelTests {
    @Test func `starts with every free share and no price`() throws {
        let model = try makeModel(available: 6)

        #expect(model.shares == 6)
        #expect(model.priceState == .none)
        #expect(model.canGetPrice)
        #expect(!model.canSell)
        #expect(model.proceeds == nil)
        #expect(model.sharesMessage == nil)
    }

    @Test func `getting a price shows the proceeds, realized gain and cash after`() async throws {
        let quote = try makeQuote(price: "12.5")
        let model = try makeModel(available: 10, cash: 100, quotes: FakeQuotes(.success(quote)))
        model.shares = 4

        await model.getPrice()

        #expect(model.priceState == .priced(quote))
        #expect(model.proceeds == Money(50))
        #expect(model.realizedGain == Money(10))
        #expect(model.cashAfter == Money(150))
        #expect(model.canSell)
    }

    @Test func `changing shares reprices without a new request`() async throws {
        let quotes = try FakeQuotes(.success(makeQuote(price: "12")))
        let model = try makeModel(available: 10, quotes: quotes)
        await model.getPrice()

        model.shares = 2

        #expect(model.proceeds == Money(24))
        #expect(quotes.requestCount == 1)
    }

    @Test(arguments: [0, 7])
    func `shares outside the free shares explain themselves and can't be sold`(shares: Int) async throws {
        let model = try makeModel(available: 6, quotes: FakeQuotes(.success(makeQuote(price: "12"))))
        await model.getPrice()

        model.shares = shares

        #expect(model.sharesMessage == "Sell between 1 and 6 shares.")
        #expect(!model.canSell)
        #expect(model.sell() == nil)
    }

    @Test func `a purchase with no free shares says so and can't be sold or priced`() throws {
        let model = try makeModel(available: 0)

        #expect(model.sharesMessage == "No shares of this purchase are free. Cancel an open sell order to free its shares.")
        #expect(!model.canGetPrice)
        #expect(!model.canSell)
    }

    @Test func `a failed quote shows its reason and asks for a key when one is missing`() async throws {
        let model = try makeModel(available: 10, quotes: FakeQuotes(.failure(.missingAPIKey)))

        await model.getPrice()

        #expect(model.priceState == .failed(QuoteError.missingAPIKey.localizedDescription))
        #expect(model.needsAPIKey)
        #expect(!model.canSell)
    }

    @Test func `selling makes a sale of the purchase now at the quoted price`() async throws {
        let quote = try makeQuote(price: "12.3456", source: .close(sessionDate: "2026-10-23"))
        let model = try makeModel(available: 10, quotes: FakeQuotes(.success(quote)))
        model.shares = 3
        await model.getPrice()

        let sale = try #require(model.sell())

        #expect(sale.id == Self.saleID)
        #expect(sale.purchaseID == fixedPurchaseID)
        #expect(sale.shares == 3)
        #expect(sale.pricePerShare == quote.price)
        #expect(sale.priceSource == .close(sessionDate: "2026-10-23"))
        // When the user sells, not when the close was set (ADR-0016).
        #expect(sale.soldAt == Self.now)
    }

    @Test func `a quote marked as a limit fill can't be sold at`() async throws {
        let quote = try makeQuote(price: "12", source: .limitOrderFill(sessionDate: "2026-10-23"))
        let model = try makeModel(available: 10, quotes: FakeQuotes(.success(quote)))

        await model.getPrice()

        #expect(model.proceeds == nil)
        #expect(!model.canSell)
    }

    private static let now = Date(timeIntervalSince1970: 1_793_100_000)
    private static let saleID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!

    private func makeModel(
        available: Int,
        cash: Decimal = 0,
        quotes: FakeQuotes = FakeQuotes(.failure(.missingAPIKey)),
    ) throws -> SaleModel {
        let purchase = try Purchase(
            id: fixedPurchaseID,
            ticker: Ticker("VTI"),
            shares: 10,
            pricePerShare: 10,
            pricedAt: Date(timeIntervalSince1970: 1_793_000_000),
            priceSource: .liveQuote(delayed: false),
        )
        return SaleModel(
            purchase: purchase,
            availableShares: available,
            cashBalance: Money(cash),
            quotes: quotes,
            clock: { Self.now },
            saleID: Self.saleID,
        )
    }
}
