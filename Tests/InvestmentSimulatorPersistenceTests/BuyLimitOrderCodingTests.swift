import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPersistence
import Testing

struct BuyLimitOrderCodingTests {
    let codec = JSONExperimentCodec()

    @Test func `open, filled and cancelled buy orders survive a round trip`() throws {
        let open = try makeBuyLimitOrder(id: 1, shares: 2, limitPrice: "9.5")
        let filled = try makeBuyLimitOrder(id: 2, shares: 3, limitPrice: "9")
        let cancelled = try makeBuyLimitOrder(id: 3, shares: 1, limitPrice: "8")
        let experiment = try Experiment(cashBalance: Money(100))
            .placing(open)
            .placing(filled)
            .placing(cancelled)
            .fillingBuyOrder(orderID: filled.id, on: "2026-10-27")
            .cancelling(orderID: cancelled.id, at: Date(timeIntervalSince1970: 1_793_003_600))

        let decoded = try codec.decode(codec.encode(experiment))

        #expect(decoded == experiment)
    }

    @Test func `buy order is written with its ticker, a string price and ISO 8601 dates`() throws {
        let order = try makeBuyLimitOrder(id: 1, shares: 2, limitPrice: "9.5")
        let experiment = try Experiment(cashBalance: Money(100)).placing(order)

        let data = try codec.encode(experiment)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let written = try #require((json["buyLimitOrders"] as? [[String: Any]])?.first)

        #expect(written["id"] as? String == "00000000-0000-0000-0000-0000000000B1")
        #expect(written["ticker"] as? String == "VTI")
        #expect(written["shares"] as? Int == 2)
        #expect(written["limitPrice"] as? String == "9.5")
        #expect(written["placedAt"] as? String == "2026-10-26T07:33:20.000Z")
        #expect(written["expiresAt"] as? String == "2027-01-24T08:33:20.000Z")
        #expect(written.keys.contains("filledOn") == false)
        #expect(written.keys.contains("cancelledAt") == false)
    }

    @Test func `fill purchase is written with its source and session`() throws {
        let order = try makeBuyLimitOrder(id: 1, shares: 2, limitPrice: "9.5")
        let experiment = try Experiment(cashBalance: Money(100))
            .placing(order)
            .fillingBuyOrder(orderID: order.id, on: "2026-10-27")

        let data = try codec.encode(experiment)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let purchase = try #require((json["purchases"] as? [[String: Any]])?.first)
        let written = try #require((json["buyLimitOrders"] as? [[String: Any]])?.first)

        #expect(purchase["id"] as? String == "00000000-0000-0000-0000-0000000000B1")
        #expect(purchase["priceSource"] as? String == "limitOrderFill")
        #expect(purchase["sessionDate"] as? String == "2026-10-27")
        #expect(written["filledOn"] as? String == "2026-10-27")
    }

    @Test(arguments: [
        (#""ticker": "VT I""#, ExperimentCodingError.invalidTicker("VT I")),
        (#""limitPrice": "12abc""#, .invalidLimitPrice("12abc")),
        (#""placedAt": "yesterday""#, .invalidOrderDate("yesterday")),
        (#""expiresAt": "later""#, .invalidOrderDate("later")),
        (#""cancelledAt": "soon""#, .invalidOrderDate("soon")),
    ])
    func `malformed buy order is rejected`(field: String, error: ExperimentCodingError) {
        #expect(throws: error) {
            try codec.decode(buyOrderFile(replacing: field))
        }
    }

    @Test func `buy order with no shares is rejected by the domain`() {
        #expect(throws: LimitOrderError.nonPositiveShares(0)) {
            try codec.decode(buyOrderFile(replacing: #""shares": 0"#))
        }
    }

    @Test func `filled buy order without its purchase is rejected by the domain`() throws {
        let orderID = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000B1"))

        #expect(throws: ExperimentError.mismatchedFillPurchase(orderID)) {
            try codec.decode(buyOrderFile(replacing: #""filledOn": "2026-10-27""#))
        }
    }

    @Test func `fill mismatch error describes the problem`() {
        let error: any Error = ExperimentError.mismatchedFillPurchase(UUID())
        let description = "A buy limit order's fill doesn't match the experiment's purchases."

        #expect(error.localizedDescription == description)
        #expect((error as NSError).localizedFailureReason == description)
    }

    /// A valid version 5 file with no purchases and one open buy order, with
    /// `field`, a `"key": value` pair, in place of the order's pair with that
    /// key, or added when the order has none.
    private func buyOrderFile(replacing field: String) -> Data {
        var order = [
            #""id": "00000000-0000-0000-0000-0000000000B1""#,
            #""ticker": "VTI""#,
            #""shares": 1"#,
            #""limitPrice": "9""#,
            #""placedAt": "2026-10-26T07:33:20.000Z""#,
            #""expiresAt": "2027-01-24T08:33:20.000Z""#,
        ]
        let key = field.prefix { $0 != ":" }
        order = order.contains { $0.hasPrefix(key) }
            ? order.map { $0.hasPrefix(key) ? field : $0 }
            : order + [field]
        let orderJSON = "{" + order.joined(separator: ", ") + "}"
        return Data(#"""
        {"schemaVersion": 5, "cashBalance": "100", "purchases": [], "limitOrders": [],
         "buyLimitOrders": [\#(orderJSON)]}
        """#.utf8)
    }

    private func makeBuyLimitOrder(id: Int, shares: Int, limitPrice: String) throws -> BuyLimitOrder {
        try BuyLimitOrder.placed(
            id: #require(UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000000B%d", id))),
            ticker: Ticker("VTI"),
            shares: shares,
            limitPrice: Money(#require(Decimal(string: limitPrice))),
            at: Date(timeIntervalSince1970: 1_793_000_000),
        )
    }
}
