import Foundation
import GRDB
import InvestmentSimulatorCore
@testable import InvestmentSimulatorPersistence
import Testing

/// A database an earlier version of the app made is migrated in place
/// (ADR-0021). `@testable` reaches the internal schema to build one.
struct ExperimentSchemaMigrationTests {
    @Test func `a sale stored before quote times were recorded loads without one`() async throws {
        let queue = try DatabaseQueue()
        try ExperimentSchema.migrator().migrate(queue, upTo: "v1")
        let id = ExperimentID()
        let purchaseID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let saleID = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000C1"))
        let pricedAt = Date(timeIntervalSince1970: 1_793_000_000)
        let soldAt = Date(timeIntervalSince1970: 1_793_300_000)
        try await queue.write { database in
            let key = id.rawValue.uuidString
            try database.execute(sql: "INSERT INTO experiment (id, cash_balance) VALUES (?, '125')", arguments: [key])
            try database.execute(sql: """
            INSERT INTO purchase (experiment_id, id, position, ticker, shares, price_per_share,
                                  priced_at, price_source, delayed)
            VALUES (?, ?, 0, 'VTI', 10, '10', ?, 'liveQuote', 0)
            """, arguments: [key, purchaseID.uuidString, pricedAt.timeIntervalSinceReferenceDate])
            try database.execute(sql: """
            INSERT INTO sale (experiment_id, id, position, purchase_id, shares, price_per_share,
                              sold_at, price_source, delayed)
            VALUES (?, ?, 0, ?, 2, '12.5', ?, 'liveQuote', 1)
            """, arguments: [key, saleID.uuidString, purchaseID.uuidString, soldAt.timeIntervalSinceReferenceDate])
        }

        let repository = try GRDBExperimentRepository(writer: queue)
        let experiment = try await repository.load(id)

        let expected = try Sale(
            id: saleID,
            purchaseID: purchaseID,
            shares: 2,
            pricePerShare: #require(Decimal(string: "12.5")),
            soldAt: soldAt,
            quotedAt: nil,
            priceSource: .liveQuote(delayed: true),
        )
        #expect(experiment.sales == [expected])
    }

    /// A build without a newer migration would drop what it adds on save,
    /// such as an older build clearing `quoted_at` (ADR-0026).
    @Test func `a database a newer version of the app migrated isn't opened or changed`() async throws {
        let queue = try DatabaseQueue()
        try ExperimentSchema.migrator().migrate(queue, upTo: "v1")
        try await queue.write { database in
            try database.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v99')")
        }

        #expect(throws: ExperimentDatabaseError.newerThanApp(path: queue.path)) {
            try GRDBExperimentRepository(writer: queue)
        }
        let saleColumns = try await queue.read { try $0.columns(in: "sale").map(\.name) }
        #expect(!saleColumns.contains("quoted_at"))
    }
}
