import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct LimitOrderModelTests {
    @Test func `starts selling every free share at a percent profit of zero`() throws {
        let model = try makeModel(price: "316.9961", available: 4)

        #expect(model.mode == .profitPercent)
        #expect(model.shares == 4)
        #expect(model.profitPercent == 0)
        #expect(try model.limitPrice == Money(317))
        #expect(model.canPlace)
    }

    @Test func `percent profit sets the limit price, rounded up to cents`() throws {
        let model = try makeModel(price: "316.9961", available: 4)

        model.profitPercent = 10

        #expect(try model.limitPrice == Money(#require(Decimal(string: "348.70"))))
        #expect(model.priceMessage == nil)
    }

    @Test func `negative percent profit can't be placed`() throws {
        let model = try makeModel(price: "10", available: 4)

        model.profitPercent = -1

        #expect(model.limitPrice == nil)
        #expect(model.priceMessage == "Profit can't be negative.")
        #expect(!model.canPlace)
        #expect(model.place() == nil)
    }

    @Test func `typed limit price is rounded to cents with bankers rounding`() throws {
        let model = try makeModel(price: "10", available: 4)
        model.mode = .limitPrice

        model.enteredPrice = try #require(Decimal(string: "12.125"))

        #expect(try model.limitPrice == Money(#require(Decimal(string: "12.12"))))
    }

    @Test(arguments: ["0", "0.004", "-1"])
    func `limit price must be above zero after rounding`(entered: String) throws {
        let model = try makeModel(price: "10", available: 4)
        model.mode = .limitPrice

        model.enteredPrice = try #require(Decimal(string: entered))

        #expect(model.limitPrice == nil)
        #expect(model.priceMessage == "Enter a limit price above zero.")
        #expect(!model.canPlace)
    }

    @Test func `typed limit price starts at the purchase price`() throws {
        let model = try makeModel(price: "316.9961", available: 4)

        model.mode = .limitPrice

        #expect(try model.limitPrice == Money(#require(Decimal(string: "317.00"))))
    }

    @Test func `profit is the gain over the purchase price for the shares sold`() throws {
        let model = try makeModel(price: "316.9961", available: 4)
        model.profitPercent = 10
        model.shares = 3

        // (348.70 - 316.9961) × 3 = 95.1117
        #expect(try model.profit == Money(#require(Decimal(string: "95.11"))))
    }

    @Test(arguments: [0, 5])
    func `shares must be between one and the free shares`(shares: Int) throws {
        let model = try makeModel(price: "10", available: 4)

        model.shares = shares

        #expect(model.sharesMessage == "Sell between 1 and 4 shares.")
        #expect(!model.canPlace)
    }

    @Test func `purchase with no free shares can't be placed`() throws {
        let model = try makeModel(price: "10", available: 0)

        #expect(model.sharesMessage == "Every share of this purchase is in an open order.")
        #expect(!model.canPlace)
    }

    @Test func `negative free shares can't be placed`() throws {
        let model = try makeModel(price: "10", available: -1)

        #expect(model.sharesMessage == "Every share of this purchase is in an open order.")
        #expect(!model.canPlace)
    }

    @Test func `expiry is 90 calendar days from now`() throws {
        let model = try makeModel(price: "10", available: 4)

        #expect(model.expiresAt == LimitOrder.expiry(forPlacedAt: fixedNow))
    }

    @Test func `placing makes the order shown`() throws {
        let model = try makeModel(price: "10", available: 4)
        model.profitPercent = 25
        model.shares = 2

        let order = try #require(model.place())

        #expect(order.id == fixedOrderID)
        #expect(order.purchaseID == fixedPurchaseID)
        #expect(order.shares == 2)
        #expect(try order.limitPrice == Money(#require(Decimal(string: "12.50"))))
        #expect(order.placedAt == fixedNow)
        #expect(order.expiresAt == model.expiresAt)
    }

    private func makeModel(price: String, available: Int) throws -> LimitOrderModel {
        try LimitOrderModel(
            purchase: Purchase(
                id: fixedPurchaseID,
                ticker: Ticker("VTI"),
                shares: 10,
                pricePerShare: #require(Decimal(string: price)),
                pricedAt: Date(timeIntervalSince1970: 1_793_000_000),
                priceSource: .liveQuote(delayed: false),
            ),
            availableShares: available,
            now: fixedNow,
            orderID: fixedOrderID,
        )
    }
}

let fixedNow = Date(timeIntervalSince1970: 1_793_100_000)
let fixedOrderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
