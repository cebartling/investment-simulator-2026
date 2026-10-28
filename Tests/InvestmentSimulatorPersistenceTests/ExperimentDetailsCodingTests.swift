import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPersistence
import Testing

/// The name, notes and created date schema version 6 adds (PIN-408).
struct ExperimentDetailsCodingTests {
    let codec = JSONExperimentCodec()

    @Test func `details survive a round trip`() throws {
        let experiment = try Experiment(
            cashBalance: Money(100),
            name: "Index funds",
            notes: "Buy and hold.\nRebalance yearly.",
            createdAt: Self.created,
        )

        #expect(try codec.decode(codec.encode(experiment)) == experiment)
    }

    @Test func `details are written as strings with an ISO 8601 date`() throws {
        let experiment = try Experiment(
            cashBalance: Money(100),
            name: "Index funds",
            notes: "Hold",
            createdAt: Self.created,
        )

        let json = try object(codec.encode(experiment))

        #expect(json["schemaVersion"] as? Int == 6)
        #expect(json["name"] as? String == "Index funds")
        #expect(json["notes"] as? String == "Hold")
        #expect(json["createdAt"] as? String == "2026-10-15T09:46:40.000Z")
    }

    @Test func `missing details are left out of the file`() throws {
        let json = try object(codec.encode(Experiment(cashBalance: Money(100))))

        #expect(json["name"] == nil)
        #expect(json["notes"] == nil)
        #expect(json["createdAt"] == nil)
    }

    @Test func `details are read from the file`() throws {
        let data = Data(#"""
        {"schemaVersion": 6, "cashBalance": "100", "purchases": [], "limitOrders": [], "buyLimitOrders": [],
         "name": "Index funds", "notes": "Hold", "createdAt": "2026-10-15T09:46:40.000Z"}
        """#.utf8)

        let experiment = try codec.decode(data)

        #expect(experiment.name == "Index funds")
        #expect(experiment.notes == "Hold")
        #expect(experiment.createdAt == Self.created)
    }

    @Test func `malformed created date is rejected`() {
        let data = Data(#"""
        {"schemaVersion": 6, "cashBalance": "100", "purchases": [], "limitOrders": [], "buyLimitOrders": [],
         "createdAt": "October 15"}
        """#.utf8)

        #expect(throws: ExperimentCodingError.invalidCreatedDate("October 15")) {
            try codec.decode(data)
        }
    }

    @Test func `malformed created date error describes the problem`() {
        let error = ExperimentCodingError.invalidCreatedDate("October 15")

        #expect(error.localizedDescription == #"The experiment's created date "October 15" isn't a valid date."#)
    }

    @Test func `version 5 file is created at its earliest purchase or order`() throws {
        // The buy order was placed first, before the purchase and the sell.
        let data = Data(#"""
        {"schemaVersion": 5, "cashBalance": "100", "purchases": [
          {"id": "00000000-0000-0000-0000-000000000001", "ticker": "VTI", "shares": 5,
           "pricePerShare": "10", "pricedAt": "2026-10-26T07:33:20.000Z",
           "priceSource": "liveQuote", "delayed": false}
        ], "limitOrders": [
          {"id": "00000000-0000-0000-0000-0000000000A1", "purchaseID": "00000000-0000-0000-0000-000000000001",
           "shares": 1, "limitPrice": "12", "placedAt": "2026-10-27T07:33:20.000Z",
           "expiresAt": "2027-01-25T08:33:20.000Z"}
        ], "buyLimitOrders": [
          {"id": "00000000-0000-0000-0000-0000000000B1", "ticker": "VTI", "shares": 1, "limitPrice": "9",
           "placedAt": "2026-10-15T09:46:40.000Z", "expiresAt": "2027-01-13T10:46:40.000Z"}
        ]}
        """#.utf8)

        let experiment = try codec.decode(data)

        #expect(experiment.createdAt == Self.created)
        #expect(experiment.name == nil)
        #expect(experiment.notes == nil)
    }

    @Test func `version 5 file with no purchases or orders has no created date`() throws {
        let data = Data(#"""
        {"schemaVersion": 5, "cashBalance": "100", "purchases": [], "limitOrders": [], "buyLimitOrders": []}
        """#.utf8)

        #expect(try codec.decode(data).createdAt == nil)
    }

    @Test func `version 2 file is created at its earliest purchase`() throws {
        let data = Data(#"""
        {"schemaVersion": 2, "cashBalance": "100", "purchases": [
          {"id": "00000000-0000-0000-0000-000000000001", "ticker": "VTI", "shares": 1,
           "pricePerShare": "10", "pricedAt": "2026-10-26T07:33:20.000Z",
           "priceSource": "liveQuote", "delayed": false},
          {"id": "00000000-0000-0000-0000-000000000002", "ticker": "VTI", "shares": 1,
           "pricePerShare": "10", "pricedAt": "2026-10-15T09:46:40.000Z",
           "priceSource": "liveQuote", "delayed": false}
        ]}
        """#.utf8)

        #expect(try codec.decode(data).createdAt == Self.created)
    }

    @Test func `version 1 file has no created date`() throws {
        let data = Data(#"{"schemaVersion": 1, "cashBalance": "100"}"#.utf8)

        #expect(try codec.decode(data).createdAt == nil)
    }

    /// 2026-10-15T09:46:40Z.
    private static let created = Date(timeIntervalSince1970: 1_792_057_600)

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
