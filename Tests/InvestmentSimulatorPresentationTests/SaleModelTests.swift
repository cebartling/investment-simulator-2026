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

        #expect(
            model.sharesMessage == "No shares of this purchase are free. Cancel an open sell order to free its shares.",
        )
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

    @Test func `starts on the first purchase with free shares`() throws {
        let model = try makeModel(choices: [
            makeChoice(price: "10", available: 0),
            makeChoice(id: Self.secondPurchaseID, price: "20", available: 6),
        ])

        #expect(model.selectedPurchaseID == Self.secondPurchaseID)
        #expect(model.purchase.id == Self.secondPurchaseID)
        #expect(model.availableShares == 6)
        #expect(model.shares == 6)
    }

    @Test func `starts on the purchase asked for, even with no free shares`() throws {
        let model = try makeModel(
            choices: [
                makeChoice(price: "10", available: 0),
                makeChoice(id: Self.secondPurchaseID, price: "20", available: 6),
            ],
            selecting: fixedPurchaseID,
        )

        #expect(model.purchase.id == fixedPurchaseID)
        #expect(model.shares == 0)
        #expect(!model.canGetPrice)
    }

    @Test func `starts on the first purchase when none has free shares`() throws {
        let model = try makeModel(choices: [
            makeChoice(price: "10", available: 0),
            makeChoice(id: Self.secondPurchaseID, price: "20", available: 0),
        ])

        #expect(model.purchase.id == fixedPurchaseID)
    }

    @Test func `choosing another purchase takes its free shares and keeps the price`() async throws {
        let quotes = try FakeQuotes(.success(makeQuote(price: "12.5")))
        let model = try makeModel(
            choices: [
                makeChoice(price: "10", available: 10),
                makeChoice(id: Self.secondPurchaseID, price: "20", available: 3),
            ],
            quotes: quotes,
        )
        await model.getPrice()

        model.selectedPurchaseID = Self.secondPurchaseID

        #expect(model.shares == 3)
        #expect(quotes.requestCount == 1)
        // 37.50 less 3 shares at 20.
        #expect(try model.realizedGain == Money(#require(Decimal(string: "-22.5"))))
        #expect(model.sell()?.purchaseID == Self.secondPurchaseID)
    }

    private static let now = Date(timeIntervalSince1970: 1_793_100_000)
    private static let saleID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
    private static let secondPurchaseID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private func makeModel(
        available: Int,
        cash: Decimal = 0,
        quotes: FakeQuotes = FakeQuotes(.failure(.missingAPIKey)),
    ) throws -> SaleModel {
        try makeModel(choices: [makeChoice(price: "10", available: available)], cash: cash, quotes: quotes)
    }

    private func makeModel(
        choices: [SellablePurchase],
        selecting purchaseID: UUID? = nil,
        cash: Decimal = 0,
        quotes: FakeQuotes = FakeQuotes(.failure(.missingAPIKey)),
    ) throws -> SaleModel {
        SaleModel(
            choices: choices,
            selecting: purchaseID,
            cashBalance: Money(cash),
            quotes: quotes,
            clock: { Self.now },
            saleID: Self.saleID,
        )
    }
}
