import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPersistence
import Testing

/// The market sales schema version 7 adds (ADR-0016).
struct SaleCodingTests {
    let codec = JSONExperimentCodec()

    @Test func `sales priced at a live quote and at a close survive a round trip`() throws {
        let experiment = try experimentWithPurchase()
            .selling(makeSale(id: 1, shares: 2, price: "348.7123", source: .liveQuote(delayed: true)))
            .selling(makeSale(id: 2, shares: 1, price: "350", source: .close(sessionDate: "2026-10-23")))

        #expect(try codec.decode(codec.encode(experiment)) == experiment)
    }

    @Test func `sale is written with a string price, an ISO 8601 date and its source`() throws {
        let experiment = try experimentWithPurchase()
            .selling(makeSale(id: 1, shares: 2, price: "348.7123", source: .liveQuote(delayed: true)))
            .selling(makeSale(id: 2, shares: 1, price: "350", source: .close(sessionDate: "2026-10-23")))

        let json = try object(codec.encode(experiment))
        let written = try #require(json["sales"] as? [[String: Any]])

        #expect(json["schemaVersion"] as? Int == 7)
        #expect(written[0]["id"] as? String == "00000000-0000-0000-0000-0000000000C1")
        #expect(written[0]["purchaseID"] as? String == "00000000-0000-0000-0000-000000000001")
        #expect(written[0]["shares"] as? Int == 2)
        #expect(written[0]["pricePerShare"] as? String == "348.7123")
        #expect(written[0]["soldAt"] as? String == "2026-10-26T07:33:20.000Z")
        #expect(written[0]["priceSource"] as? String == "liveQuote")
        #expect(written[0]["delayed"] as? Bool == true)
        #expect(written[1]["priceSource"] as? String == "close")
        #expect(written[1]["sessionDate"] as? String == "2026-10-23")
    }

    @Test func `version 6 file migrates to an experiment with no sales`() throws {
        let data = Data(#"""
        {"schemaVersion": 6, "cashBalance": "100", "purchases": [], "limitOrders": [], "buyLimitOrders": []}
        """#.utf8)

        #expect(try codec.decode(data).sales.isEmpty)
    }

    @Test func `a reopened sale's proceeds aren't added to cash again`() throws {
        let data = saleFile(cashBalance: "150")

        #expect(try codec.decode(data).cashBalance == Money(150))
    }

    @Test(arguments: [
        (#""priceSource": "limitOrderFill""#, ExperimentCodingError.invalidSalePriceSource("limitOrderFill")),
        (#""priceSource": "close""#, ExperimentCodingError.invalidSalePriceSource("close")),
        (#""pricePerShare": "12abc""#, ExperimentCodingError.invalidSalePrice("12abc")),
        (#""soldAt": "yesterday""#, ExperimentCodingError.invalidSaleDate("yesterday")),
    ])
    func `malformed sale fields are rejected`(field: String, error: ExperimentCodingError) {
        #expect(throws: error) {
            try codec.decode(saleFile(replacing: field))
        }
    }

    @Test func `sale of more shares than the purchase has free is rejected by the domain`() {
        #expect(throws: ExperimentError.insufficientShares(requested: 6, available: 5)) {
            try codec.decode(saleFile(replacing: #""shares": 6"#))
        }
    }

    @Test func `sale with no shares is rejected by the domain`() {
        #expect(throws: SaleError.nonPositiveShares(0)) {
            try codec.decode(saleFile(replacing: #""shares": 0"#))
        }
    }

    @Test(arguments: [
        (
            ExperimentCodingError.invalidSalePrice("12abc"),
            #"A sale's price "12abc" isn't a valid amount."#,
        ),
        (
            ExperimentCodingError.invalidSaleDate("yesterday"),
            #"A sale's date "yesterday" isn't a valid date."#,
        ),
        (
            ExperimentCodingError.invalidSalePriceSource("limitOrderFill"),
            #"A sale's price source "limitOrderFill" isn't recognized."#,
        ),
    ])
    func `malformed sale errors describe the problem`(error: ExperimentCodingError, description: String) {
        #expect(error.localizedDescription == description)
    }

    @Test func `sale domain errors describe the problem`() {
        #expect(SaleError.nonPositiveShares(0).localizedDescription == "A sale must be for at least one share.")
        #expect(SaleError.nonPositivePrice(0).localizedDescription == "A sale's price must be more than zero.")
    }

    /// A valid version 7 file with one purchase of 5 shares and a sale of 1
    /// at a live quote, with `field`, a `"key": value` pair, in place of the
    /// sale's pair with that key.
    private func saleFile(cashBalance: String = "1", replacing field: String? = nil) -> Data {
        var sale = [
            #""id": "00000000-0000-0000-0000-0000000000C1""#,
            #""purchaseID": "00000000-0000-0000-0000-000000000001""#,
            #""shares": 1"#,
            #""pricePerShare": "12""#,
            #""soldAt": "2026-10-26T07:33:20.000Z""#,
            #""priceSource": "liveQuote""#,
            #""delayed": false"#,
        ]
        if let field {
            let key = field.prefix { $0 != ":" }
            sale = sale.map { $0.hasPrefix(key) ? field : $0 }
        }
        let saleJSON = "{" + sale.joined(separator: ", ") + "}"
        return Data(#"""
        {"schemaVersion": 7, "cashBalance": "\#(cashBalance)", "purchases": [
          {"id": "00000000-0000-0000-0000-000000000001", "ticker": "VTI", "shares": 5,
           "pricePerShare": "10", "pricedAt": "2026-10-26T07:33:20.000Z",
           "priceSource": "liveQuote", "delayed": false}
        ], "limitOrders": [], "buyLimitOrders": [], "sales": [\#(saleJSON)]}
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

    private func makeSale(id: Int, shares: Int, price: String, source: SalePriceSource) throws -> Sale {
        try Sale(
            id: #require(UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000000C%d", id))),
            purchaseID: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            shares: shares,
            pricePerShare: #require(Decimal(string: price)),
            soldAt: Date(timeIntervalSince1970: 1_793_000_000),
            priceSource: source,
        )
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
