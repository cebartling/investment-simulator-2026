import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPersistence
import Testing

struct PurchaseCodingTests {
    let codec = JSONExperimentCodec()

    @Test func `purchases survive a round trip`() throws {
        let experiment = try Experiment(cashBalance: Money(78), purchases: [
            makePurchase(id: 1, shares: 1, price: "10", source: .liveQuote(delayed: true)),
            makePurchase(id: 2, shares: 1, price: "12.3456", source: .close(sessionDate: "2026-10-23")),
            makePurchase(id: 3, shares: 4, price: "0.0001", source: .liveQuote(delayed: false)),
        ])

        let decoded = try codec.decode(codec.encode(experiment))

        #expect(decoded == experiment)
    }

    @Test func `purchase is written with string amounts and an ISO 8601 date`() throws {
        let experiment = try Experiment(cashBalance: Money(0), purchases: [
            makePurchase(id: 1, shares: 3, price: "316.9961", source: .close(sessionDate: "2026-10-23")),
        ])

        let data = try codec.encode(experiment)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let purchase = try #require((json["purchases"] as? [[String: Any]])?.first)

        #expect(purchase["id"] as? String == "00000000-0000-0000-0000-000000000001")
        #expect(purchase["ticker"] as? String == "VTI")
        #expect(purchase["shares"] as? Int == 3)
        #expect(purchase["pricePerShare"] as? String == "316.9961")
        #expect(purchase["pricedAt"] as? String == "2026-10-26T07:33:20.000Z")
        #expect(purchase["priceSource"] as? String == "close")
        #expect(purchase["sessionDate"] as? String == "2026-10-23")
        #expect(purchase["delayed"] == nil)
    }

    @Test func `version 2 file decodes`() throws {
        let data = Data(#"""
        {"schemaVersion": 2, "cashBalance": "500", "purchases": [
          {"id": "00000000-0000-0000-0000-000000000001", "ticker": "VTI", "shares": 2,
           "pricePerShare": "250.1", "pricedAt": "2026-10-26T07:33:20.000Z",
           "priceSource": "liveQuote", "delayed": true}
        ]}
        """#.utf8)

        let experiment = try codec.decode(data)

        #expect(try experiment == Experiment(cashBalance: Money(500), purchases: [
            makePurchase(id: 1, shares: 2, price: "250.1", source: .liveQuote(delayed: true)),
        ]))
    }

    @Test(arguments: [
        (#""ticker": "VT I""#, ExperimentCodingError.invalidTicker("VT I")),
        (#""pricePerShare": "12abc""#, .invalidPrice("12abc")),
        (#""pricedAt": "yesterday""#, .invalidDate("yesterday")),
        (#""priceSource": "rumor""#, .invalidPriceSource("rumor")),
        (#""priceSource": "close""#, .invalidPriceSource("close")),
    ])
    func `malformed purchase is rejected`(field: String, error: ExperimentCodingError) {
        #expect(throws: error) {
            try codec.decode(versionTwoFile(replacing: field))
        }
    }

    @Test func `purchase with no shares is rejected by the domain`() {
        #expect(throws: PurchaseError.nonPositiveShares(0)) {
            try codec.decode(versionTwoFile(replacing: #""shares": 0"#))
        }
    }

    /// A valid version 2 file with one purchase, with one `"key": value` pair
    /// swapped for `field`.
    private func versionTwoFile(replacing field: String) -> Data {
        var purchase = [
            #""id": "00000000-0000-0000-0000-000000000001""#,
            #""ticker": "VTI""#,
            #""shares": 1"#,
            #""pricePerShare": "10""#,
            #""pricedAt": "2026-10-26T07:33:20.000Z""#,
            #""priceSource": "liveQuote""#,
            #""delayed": false"#,
        ]
        let key = field.prefix { $0 != ":" }
        purchase = purchase.map { $0.hasPrefix(key) ? field : $0 }
        let purchaseJSON = "{" + purchase.joined(separator: ", ") + "}"
        return Data(#"{"schemaVersion": 2, "cashBalance": "1", "purchases": [\#(purchaseJSON)]}"#.utf8)
    }

    private func makePurchase(id: Int, shares: Int, price: String, source: PriceSource) throws -> Purchase {
        try Purchase(
            id: #require(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))),
            ticker: Ticker("VTI"),
            shares: shares,
            pricePerShare: #require(Decimal(string: price)),
            pricedAt: Date(timeIntervalSince1970: 1_793_000_000),
            priceSource: source,
        )
    }
}
