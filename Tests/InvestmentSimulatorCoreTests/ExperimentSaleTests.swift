import Foundation
import InvestmentSimulatorCore
import Testing

/// Market sales of a purchase's shares (ADR-0016).
struct ExperimentSaleTests {
    @Test func `new experiment has no sales`() throws {
        #expect(try Experiment(cashBalance: Money(100)).sales.isEmpty)
        #expect(Experiment.empty.sales.isEmpty)
    }

    @Test func `selling adds the proceeds to cash and records the sale`() throws {
        let experiment = try experimentWithPurchase(shares: 10)
        let sale = try makeSale(shares: 4, price: "12.5")

        let sold = try experiment.selling(sale)

        #expect(sold.cashBalance == experiment.cashBalance + Money(50))
        #expect(sold.sales == [sale])
        #expect(sold.purchases == experiment.purchases)
    }

    @Test func `sold shares are no longer available, for a sell order too`() throws {
        let sold = try experimentWithPurchase(shares: 10).selling(makeSale(shares: 4, price: "12"))
        let purchase = try #require(sold.purchases.first)

        #expect(sold.availableShares(of: purchase, at: Self.later) == 6)
        #expect(throws: ExperimentError.insufficientShares(requested: 7, available: 6)) {
            try sold.placing(makeLimitOrder(shares: 7, placedAt: Self.later))
        }
    }

    @Test func `a sale can sell every available share`() throws {
        let sold = try experimentWithPurchase(shares: 10).selling(makeSale(shares: 10, price: "12"))
        let purchase = try #require(sold.purchases.first)

        #expect(sold.availableShares(of: purchase, at: Self.later) == 0)
    }

    @Test func `selling more than the available shares is rejected`() throws {
        let experiment = try experimentWithPurchase(shares: 10)

        #expect(throws: ExperimentError.insufficientShares(requested: 11, available: 10)) {
            try experiment.selling(makeSale(shares: 11, price: "12"))
        }
    }

    @Test func `shares an open sell order reserves can't be sold`() throws {
        let experiment = try experimentWithPurchase(shares: 10).placing(makeLimitOrder(shares: 7))

        #expect(throws: ExperimentError.insufficientShares(requested: 4, available: 3)) {
            try experiment.selling(makeSale(shares: 4, price: "12", soldAt: Self.later))
        }
    }

    @Test func `shares a cancelled order freed can be sold`() throws {
        let order = try makeLimitOrder(shares: 7)
        let experiment = try experimentWithPurchase(shares: 10)
            .placing(order)
            .cancelling(orderID: order.id, at: Self.later)

        let sold = try experiment.selling(makeSale(shares: 10, price: "12", soldAt: Self.later))

        #expect(sold.sales.count == 1)
    }

    @Test func `selling from an unknown purchase is rejected`() throws {
        let experiment = try experimentWithPurchase(shares: 10)

        #expect(throws: ExperimentError.unknownPurchase(Self.secondPurchaseID)) {
            try experiment.selling(makeSale(purchaseID: Self.secondPurchaseID, shares: 1, price: "12"))
        }
    }

    @Test func `sales survive every other change to the experiment`() throws {
        let sell = try makeLimitOrder(shares: 2, placedAt: Self.later)
        let cancelled = try makeLimitOrder(id: Self.secondSellID, shares: 1, placedAt: Self.later)
        let buy = try makeBuyLimitOrder(shares: 1, limitPrice: "9", placedAt: Self.later)
        let sold = try experimentWithPurchase(shares: 10).selling(makeSale(shares: 4, price: "12"))

        let changed = try sold
            .purchasing(makePurchase(id: Self.secondPurchaseID, shares: 1, price: "10"), at: Self.later)
            .placing(sell)
            .placing(cancelled)
            .placing(buy)
            .filling(orderID: sell.id, on: "2026-10-23")
            .fillingBuyOrder(orderID: buy.id, on: "2026-10-23")
            .cancelling(orderID: cancelled.id, at: Self.later.addingTimeInterval(60))
            .editingDetails(name: "Renamed", notes: nil)

        #expect(changed.sales == sold.sales)
    }

    @Test func `reopening an experiment with a sale doesn't credit its proceeds again`() throws {
        let sold = try experimentWithPurchase(shares: 10).selling(makeSale(shares: 4, price: "12.5"))

        let reopened = try reopen(sold)

        #expect(reopened == sold)
        #expect(reopened.cashBalance == Money(950))
    }

    @Test func `reopening replays sales and sell placements in time order`() throws {
        // Every step is valid in this order. Replaying every placement first
        // finds the first sale over-reserved; replaying every sale first
        // leaves too few shares for the first order.
        let first = try makeLimitOrder(shares: 6, placedAt: Self.at(1))
        let second = try makeLimitOrder(id: Self.secondSellID, shares: 6, placedAt: Self.at(4))
        let experiment = try experimentWithPurchase(shares: 10)
            .placing(first)
            .selling(makeSale(shares: 4, price: "12", soldAt: Self.at(2)))
            .cancelling(orderID: first.id, at: Self.at(3))
            .placing(second)
            .cancelling(orderID: second.id, at: Self.at(5))
            .selling(makeSale(id: Self.secondSaleID, shares: 6, price: "13", soldAt: Self.at(6)))

        #expect(try reopen(experiment) == experiment)
    }

    @Test func `a sale and a placement at the same instant survive reopening, whichever came first`() throws {
        // The sale was made first; reopening places the order first. At one
        // instant each sees the other's shares as taken (ADR-0016).
        let order = try makeLimitOrder(shares: 6, placedAt: Self.at(1))
        let experiment = try experimentWithPurchase(shares: 10)
            .selling(makeSale(shares: 4, price: "12", soldAt: Self.at(1)))
            .placing(order)

        #expect(try reopen(experiment) == experiment)
    }

    @Test func `a sale and a placement at the same instant can't take more than the purchase has`() throws {
        let purchase = try makePurchase(shares: 10, price: "10")

        #expect(throws: ExperimentError.insufficientShares(requested: 5, available: 4)) {
            try Experiment(
                cashBalance: Money(1000),
                purchases: [purchase],
                limitOrders: [makeLimitOrder(shares: 6, placedAt: Self.at(1))],
                sales: [makeSale(shares: 5, price: "12", soldAt: Self.at(1))],
            )
        }
    }

    @Test func `experiment created with sales selling too many shares is rejected`() throws {
        let purchase = try makePurchase(shares: 10, price: "10")
        let sales = try [
            makeSale(shares: 6, price: "12"),
            makeSale(id: Self.secondSaleID, shares: 6, price: "12"),
        ]

        #expect(throws: ExperimentError.insufficientShares(requested: 6, available: 4)) {
            try Experiment(cashBalance: Money(1000), purchases: [purchase], sales: sales)
        }
    }

    @Test func `experiment created with a sale of an unknown purchase is rejected`() throws {
        #expect(throws: ExperimentError.unknownPurchase(Self.secondPurchaseID)) {
            try Experiment(
                cashBalance: Money(1000),
                sales: [makeSale(purchaseID: Self.secondPurchaseID, shares: 1, price: "12")],
            )
        }
    }

    @Test func `a sale sharing an id with a purchase or order is rejected`() throws {
        let purchase = try makePurchase(shares: 10, price: "10")
        let order = try makeLimitOrder(shares: 1)

        #expect(throws: ExperimentError.duplicateID(order.id)) {
            try Experiment(
                cashBalance: Money(1000),
                purchases: [purchase],
                limitOrders: [order],
                sales: [makeSale(id: order.id, shares: 1, price: "12", soldAt: Self.later)],
            )
        }
    }

    // MARK: - Header figures (PIN-408)

    @Test func `starting cash takes out sale proceeds`() throws {
        let sold = try experimentWithPurchase(shares: 10).selling(makeSale(shares: 4, price: "12.5"))

        #expect(sold.startingCash == Money(1000))
    }

    @Test func `held shares, invested cost and held tickers leave out sold shares`() throws {
        let sold = try experimentWithPurchase(shares: 10).selling(makeSale(shares: 4, price: "12.5"))
        let purchase = try #require(sold.purchases.first)

        #expect(sold.heldShares(of: purchase) == 6)
        #expect(sold.investedCost == Money(60))
        #expect(try sold.heldTickers == [Ticker("VTI")])
    }

    @Test func `a purchase sold in full is no longer held`() throws {
        let sold = try experimentWithPurchase(shares: 10).selling(makeSale(shares: 10, price: "12"))

        #expect(sold.heldTickers.isEmpty)
        #expect(sold.marketValue(prices: [:]) == .zero)
        #expect(sold.gain(prices: [:])?.amount == Money(20))
    }

    private static let now = Date(timeIntervalSince1970: 1_793_000_000)
    private static let later = now.addingTimeInterval(3600)
    private static let secondPurchaseID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let secondSellID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
    private static let secondSaleID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!

    /// `hours` hours after the purchase.
    private static func at(_ hours: Int) -> Date {
        now.addingTimeInterval(TimeInterval(hours * 3600))
    }

    private func experimentWithPurchase(shares: Int) throws -> Experiment {
        try Experiment(cashBalance: Money(1000)).purchasing(makePurchase(shares: shares, price: "10"), at: Self.now)
    }

    /// The experiment rebuilt from what its file saves.
    private func reopen(_ experiment: Experiment) throws -> Experiment {
        try Experiment(
            cashBalance: experiment.cashBalance,
            purchases: experiment.purchases,
            limitOrders: experiment.limitOrders,
            buyLimitOrders: experiment.buyLimitOrders,
            sales: experiment.sales,
            name: experiment.name,
            notes: experiment.notes,
            createdAt: experiment.createdAt,
        )
    }
}
