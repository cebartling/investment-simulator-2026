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

    @Test func `expiry is read from the file, not recalculated`() throws {
        let experiment = try codec.decode(versionThreeFile(replacing: #""expiresAt": "2026-11-01T00:00:00.000Z""#))

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
            try codec.decode(versionThreeFile(replacing: field))
        }
    }

    @Test func `limit order with no shares is rejected by the domain`() {
        #expect(throws: LimitOrderError.nonPositiveShares(0)) {
            try codec.decode(versionThreeFile(replacing: #""shares": 0"#))
        }
    }

    @Test func `limit order for a missing purchase is rejected by the domain`() throws {
        let purchaseID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000099"))

        #expect(throws: ExperimentError.unknownPurchase(purchaseID)) {
            try codec.decode(versionThreeFile(replacing: #""purchaseID": "\#(purchaseID)""#))
        }
    }

    @Test func `limit order for more shares than the purchase has is rejected by the domain`() {
        #expect(throws: ExperimentError.insufficientShares(requested: 6, available: 5)) {
            try codec.decode(versionThreeFile(replacing: #""shares": 6"#))
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
    ])
    func `limit order errors describe the problem`(error: LimitOrderError, description: String) {
        #expect(error.localizedDescription == description)
        #expect((error as NSError).localizedFailureReason == description)
    }

    @Test func `unknown purchase error describes the problem`() {
        let error: any Error = ExperimentError.unknownPurchase(UUID())
        let description = "A limit order sells shares of a purchase the experiment doesn't have."

        #expect(error.localizedDescription == description)
        #expect((error as NSError).localizedFailureReason == description)
    }

    /// A valid version 3 file with one purchase and one limit order on it,
    /// with one of the order's `"key": value` pairs swapped for `field`.
    private func versionThreeFile(replacing field: String) -> Data {
        var order = [
            #""id": "00000000-0000-0000-0000-0000000000A1""#,
            #""purchaseID": "00000000-0000-0000-0000-000000000001""#,
            #""shares": 1"#,
            #""limitPrice": "12""#,
            #""placedAt": "2026-10-26T07:33:20.000Z""#,
            #""expiresAt": "2027-01-24T08:33:20.000Z""#,
        ]
        let key = field.prefix { $0 != ":" }
        order = order.map { $0.hasPrefix(key) ? field : $0 }
        let orderJSON = "{" + order.joined(separator: ", ") + "}"
        return Data(#"""
        {"schemaVersion": 3, "cashBalance": "1", "purchases": [
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
