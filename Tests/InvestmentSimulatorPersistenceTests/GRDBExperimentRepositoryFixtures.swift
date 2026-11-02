import Foundation
import GRDB
import InvestmentSimulatorCore

/// Builders for `GRDBExperimentRepositoryTests`.
extension GRDBExperimentRepositoryTests {
    func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", number))!
    }

    func makePurchase(
        id: Int,
        shares: Int,
        price: String,
        source: PriceSource = .liveQuote(delayed: false),
    ) throws -> Purchase {
        try Purchase(
            id: uuid(id),
            ticker: Ticker("VTI"),
            shares: shares,
            pricePerShare: Decimal(string: price)!,
            pricedAt: Date(timeIntervalSince1970: 1_793_000_000),
            priceSource: source,
        )
    }

    /// Three purchases (a live quote, a close and a buy-order fill, which
    /// Core builds from its filled order), sell orders that are open, filled
    /// and cancelled, buy orders that are open, filled and cancelled, and two
    /// sales.
    func makeFullExperiment() throws -> Experiment {
        let placed = Date(timeIntervalSince1970: 1_793_100_000)
        let expires = Date(timeIntervalSince1970: 1_800_000_000)
        let filledBuy = try BuyLimitOrder(
            id: uuid(3), ticker: Ticker("VTI"), shares: 4, limitPrice: Money(50),
            placedAt: placed, expiresAt: expires, filledOn: "2026-10-27",
        )
        return try Experiment(
            cashBalance: Money(Decimal(string: "1234.56")!),
            purchases: [
                makePurchase(id: 1, shares: 10, price: "317.1234", source: .liveQuote(delayed: true)),
                makePurchase(id: 2, shares: 10, price: "300", source: .close(sessionDate: "2026-10-23")),
                filledBuy.purchase(filledOn: "2026-10-27"),
            ],
            limitOrders: [
                LimitOrder(
                    id: uuid(0xA1), purchaseID: uuid(1), shares: 2, limitPrice: Money(400),
                    placedAt: placed, expiresAt: expires,
                ),
                LimitOrder(
                    id: uuid(0xA2), purchaseID: uuid(1), shares: 3, limitPrice: Money(Decimal(string: "350.5")!),
                    placedAt: placed, expiresAt: expires, filledOn: "2026-10-28",
                ),
                LimitOrder(
                    id: uuid(0xA3), purchaseID: uuid(2), shares: 1, limitPrice: Money(500),
                    placedAt: placed, expiresAt: expires, cancelledAt: Date(timeIntervalSince1970: 1_793_200_000),
                ),
            ],
            buyLimitOrders: [
                BuyLimitOrder(
                    id: uuid(0xB1), ticker: Ticker("VXUS"), shares: 1, limitPrice: Money(20),
                    placedAt: placed, expiresAt: expires,
                ),
                filledBuy,
                BuyLimitOrder(
                    id: uuid(0xB3), ticker: Ticker("BND"), shares: 2, limitPrice: Money(10),
                    placedAt: placed, expiresAt: expires, cancelledAt: Date(timeIntervalSince1970: 1_793_200_000),
                ),
            ],
            sales: makeSales(),
            name: "Everything",
            notes: "Notes",
            createdAt: Date(timeIntervalSince1970: 1_793_000_000),
        )
    }

    /// Two sales of the second purchase, at a live quote and at a close.
    func makeSales() throws -> [Sale] {
        try [
            Sale(
                id: uuid(0xC2), purchaseID: uuid(2), shares: 2, pricePerShare: Decimal(string: "348.7123")!,
                soldAt: Date(timeIntervalSince1970: 1_793_300_000), priceSource: .liveQuote(delayed: true),
            ),
            Sale(
                id: uuid(0xC1), purchaseID: uuid(2), shares: 1, pricePerShare: 350,
                soldAt: Date(timeIntervalSince1970: 1_793_400_000), priceSource: .close(sessionDate: "2026-10-23"),
            ),
        ]
    }
}
