import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPersistence
import Testing

struct LimitOrderCodingTests {
    let codec = JSONExperimentCodec()

    @Test func `limit orders survive a round trip`() throws {
        let experiment = try experimentWithPurchase()
            .placing(makeLimitOrder(id: 1, shares: 2, limitPrice: "348.7"))
            .placing(makeLimitOrder(id: 2, shares: 3, limitPrice: "400"))

        let decoded = try codec.decode(codec.encode(experiment))

        #expect(decoded == experiment)
    }

    @Test func `limit order is written with a string price and ISO 8601 dates`() throws {
        let order = try makeLimitOrder(id: 1, shares: 2, limitPrice: "348.7")
        let experiment = try experimentWithPurchase().placing(order)

        let data = try codec.encode(experiment)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let written = try #require((json["limitOrders"] as? [[String: Any]])?.first)

        #expect(written["id"] as? String == "00000000-0000-0000-0000-0000000000A1")
        #expect(written["purchaseID"] as? String == "00000000-0000-0000-0000-000000000001")
        #expect(written["shares"] as? Int == 2)
        #expect(written["limitPrice"] as? String == "348.7")
        #expect(written["placedAt"] as? String == "2026-10-26T07:33:20.000Z")
        #expect(written["expiresAt"] as? String == "2027-01-24T08:33:20.000Z")
    }

    @Test func `filled order survives a round trip`() throws {
        let order = try makeLimitOrder(id: 1, shares: 2, limitPrice: "348.7")
        let experiment = try experimentWithPurchase().placing(order).filling(orderID: order.id, on: "2026-10-27")

        let decoded = try codec.decode(codec.encode(experiment))

        #expect(decoded == experiment)
    }

    @Test func `fill is written as its session date, and an unfilled order has none`() throws {
        let filled = try makeLimitOrder(id: 1, shares: 2, limitPrice: "348.7")
        let unfilled = try makeLimitOrder(id: 2, shares: 3, limitPrice: "400")
        let experiment = try experimentWithPurchase()
            .placing(filled)
            .placing(unfilled)
            .filling(orderID: filled.id, on: "2026-10-27")

        let data = try codec.encode(experiment)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let written = try #require(json["limitOrders"] as? [[String: Any]])

        #expect(written.map { $0["filledOn"] as? String } == ["2026-10-27", nil])
        #expect(written[1].keys.contains("filledOn") == false)
    }

    @Test func `fill is read from the file`() throws {
        let experiment = try codec.decode(orderFile(replacing: #""filledOn": "2026-10-27""#))

        #expect(experiment.limitOrders.map(\.filledOn) == ["2026-10-27"])
    }

    @Test func `version 3 file migrates to unfilled limit orders`() throws {
        let experiment = try codec.decode(orderFile(version: 3))

        #expect(experiment.limitOrders.count == 1)
        #expect(experiment.limitOrders.map(\.filledOn) == [nil])
    }

    @Test func `malformed fill date is rejected by the domain`() {
        #expect(throws: LimitOrderError.invalidSessionDate("10/27/2026")) {
            try codec.decode(orderFile(replacing: #""filledOn": "10/27/2026""#))
        }
    }

    @Test func `expiry is read from the file, not recalculated`() throws {
        let experiment = try codec.decode(orderFile(replacing: #""expiresAt": "2026-11-01T00:00:00.000Z""#))

        let order = try #require(experiment.limitOrders.first)
        #expect(order.expiresAt == Date(timeIntervalSince1970: 1_793_491_200))
    }

    @Test func `version 2 file migrates to an experiment with no limit orders`() throws {
        let data = Data(#"""
        {"schemaVersion": 2, "cashBalance": "500", "purchases": [
          {"id": "00000000-0000-0000-0000-000000000001", "ticker": "VTI", "shares": 2,
           "pricePerShare": "250.1", "pricedAt": "2026-10-26T07:33:20.000Z",
           "priceSource": "liveQuote", "delayed": true}
        ]}
        """#.utf8)

        let experiment = try codec.decode(data)

        #expect(experiment.purchases.count == 1)
        #expect(experiment.limitOrders.isEmpty)
    }

    @Test(arguments: [
        (#""limitPrice": "12abc""#, ExperimentCodingError.invalidLimitPrice("12abc")),
        (#""placedAt": "yesterday""#, .invalidOrderDate("yesterday")),
        (#""expiresAt": "later""#, .invalidOrderDate("later")),
    ])
    func `malformed limit order is rejected`(field: String, error: ExperimentCodingError) {
        #expect(throws: error) {
            try codec.decode(orderFile(replacing: field))
        }
    }

    @Test func `limit order with no shares is rejected by the domain`() {
        #expect(throws: LimitOrderError.nonPositiveShares(0)) {
            try codec.decode(orderFile(replacing: #""shares": 0"#))
        }
    }

    @Test func `limit order for a missing purchase is rejected by the domain`() throws {
        let purchaseID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000099"))

        #expect(throws: ExperimentError.unknownPurchase(purchaseID)) {
            try codec.decode(orderFile(replacing: #""purchaseID": "\#(purchaseID)""#))
        }
    }

    @Test func `limit order for more shares than the purchase has is rejected by the domain`() {
        #expect(throws: ExperimentError.insufficientShares(requested: 6, available: 5)) {
            try codec.decode(orderFile(replacing: #""shares": 6"#))
        }
    }

    @Test func `insufficient shares error describes the problem`() {
        let error: any Error = ExperimentError.insufficientShares(requested: 6, available: 5)
        let description = "A limit order sells more shares than the purchase has free."

        #expect(error.localizedDescription == description)
        #expect((error as NSError).localizedFailureReason == description)
    }

    @Test(arguments: [
        (LimitOrderError.nonPositiveShares(0), "A limit order must be for at least one share."),
        (.nonPositivePrice(.zero), "A limit order's price must be more than zero."),
        (.negativeProfitPercent(-1), "A limit order's profit can't be negative."),
        (.invalidSessionDate("10/23/2026"), "A limit order's fill date must be written yyyy-MM-dd."),
    ])
    func `limit order errors describe the problem`(error: LimitOrderError, description: String) {
        #expect(error.localizedDescription == description)
        #expect((error as NSError).localizedFailureReason == description)
    }

    @Test(arguments: [
        (ExperimentError.unknownOrder(UUID()), "The experiment has no such limit order."),
        (.orderAlreadyFilled(UUID()), "The limit order has already filled."),
        (.invalidSessionDate("10/23/2026"), "A limit order's fill date must be written yyyy-MM-dd."),
    ])
    func `fill errors describe the problem`(error: ExperimentError, description: String) {
        #expect(error.localizedDescription == description)
        #expect((error as NSError).localizedFailureReason == description)
    }

    @Test func `unknown purchase error describes the problem`() {
        let error: any Error = ExperimentError.unknownPurchase(UUID())
        let description = "A limit order sells shares of a purchase the experiment doesn't have."

        #expect(error.localizedDescription == description)
        #expect((error as NSError).localizedFailureReason == description)
    }

    /// A valid file of `version` with one purchase and one unfilled limit
    /// order on it, with `field`, a `"key": value` pair, in place of the
    /// order's pair with that key, or added when the order has none.
    private func orderFile(version: Int = 4, replacing field: String? = nil) -> Data {
        var order = [
            #""id": "00000000-0000-0000-0000-0000000000A1""#,
            #""purchaseID": "00000000-0000-0000-0000-000000000001""#,
            #""shares": 1"#,
            #""limitPrice": "12""#,
            #""placedAt": "2026-10-26T07:33:20.000Z""#,
            #""expiresAt": "2027-01-24T08:33:20.000Z""#,
        ]
        if let field {
            let key = field.prefix { $0 != ":" }
            order = order.contains { $0.hasPrefix(key) }
                ? order.map { $0.hasPrefix(key) ? field : $0 }
                : order + [field]
        }
        let orderJSON = "{" + order.joined(separator: ", ") + "}"
        return Data(#"""
        {"schemaVersion": \#(version), "cashBalance": "1", "purchases": [
          {"id": "00000000-0000-0000-0000-000000000001", "ticker": "VTI", "shares": 5,
           "pricePerShare": "10", "pricedAt": "2026-10-26T07:33:20.000Z",
           "priceSource": "liveQuote", "delayed": false}
        ], "limitOrders": [\#(orderJSON)]}
        """#.utf8)
    }

    private func experimentWithPurchase() throws -> Experiment {
        try Experiment(cashBalance: Money(0), purchases: [
            Purchase(
                id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
                ticker: Ticker("VTI"),
                shares: 5,
                pricePerShare: 317,
                pricedAt: Date(timeIntervalSince1970: 1_793_000_000),
                priceSource: .liveQuote(delayed: false),
            ),
        ])
    }

    private func makeLimitOrder(id: Int, shares: Int, limitPrice: String) throws -> LimitOrder {
        try LimitOrder.placed(
            id: #require(UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000000A%d", id))),
            purchaseID: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            shares: shares,
            limitPrice: Money(#require(Decimal(string: limitPrice))),
            at: Date(timeIntervalSince1970: 1_793_000_000),
        )
    }
}
