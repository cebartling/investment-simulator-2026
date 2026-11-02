import Foundation
import GRDB
import InvestmentSimulatorCore

/// Moves one experiment between Core's types and the schema's rows. Reading
/// rebuilds through `Experiment`'s public init, so a stored history that
/// doesn't replay fails instead of producing an invalid experiment.
enum StoredExperiment {
    private static let childTables = ["purchase", "sale", "sell_order", "buy_order"]

    // MARK: Writing

    static func insert(_ experiment: Experiment, as id: ExperimentID, into database: Database) throws {
        let key = id.rawValue.uuidString
        try database.execute(
            sql: "INSERT INTO experiment (id, cash_balance, name, notes, created_at) VALUES (?, ?, ?, ?, ?)",
            arguments: [
                key,
                experiment.cashBalance.amount.description,
                experiment.name,
                experiment.notes,
                experiment.createdAt.map(StoredValues.stored),
            ],
        )
        try insertPurchases(experiment.purchases, key, database)
        try insertSales(experiment.sales, key, database)
        try insertSellOrders(experiment.limitOrders, key, database)
        try insertBuyOrders(experiment.buyLimitOrders, key, database)
    }

    private static func insertPurchases(_ purchases: [Purchase], _ key: String, _ database: Database) throws {
        for (position, purchase) in purchases.enumerated() {
            let source = columns(of: purchase.priceSource)
            try database.execute(sql: """
            INSERT INTO purchase (experiment_id, id, position, ticker, shares, price_per_share,
                                  priced_at, price_source, delayed, session_date)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                key, purchase.id.uuidString, position, purchase.ticker.symbol, purchase.shares,
                purchase.pricePerShare.description, StoredValues.stored(purchase.pricedAt),
                source.source, source.delayed, source.sessionDate,
            ])
        }
    }

    private static func insertSales(_ sales: [Sale], _ key: String, _ database: Database) throws {
        for (position, sale) in sales.enumerated() {
            let source = columns(of: sale.priceSource)
            try database.execute(sql: """
            INSERT INTO sale (experiment_id, id, position, purchase_id, shares, price_per_share,
                              sold_at, price_source, delayed, session_date)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                key, sale.id.uuidString, position, sale.purchaseID.uuidString, sale.shares,
                sale.pricePerShare.description, StoredValues.stored(sale.soldAt),
                source.source, source.delayed, source.sessionDate,
            ])
        }
    }

    private static func insertSellOrders(_ orders: [LimitOrder], _ key: String, _ database: Database) throws {
        for (position, order) in orders.enumerated() {
            try database.execute(sql: """
            INSERT INTO sell_order (experiment_id, id, position, purchase_id, shares, limit_price,
                                    placed_at, expires_at, filled_on, cancelled_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                key, order.id.uuidString, position, order.purchaseID.uuidString, order.shares,
                order.limitPrice.amount.description, StoredValues.stored(order.placedAt),
                StoredValues.stored(order.expiresAt), order.filledOn, order.cancelledAt.map(StoredValues.stored),
            ])
        }
    }

    private static func insertBuyOrders(_ orders: [BuyLimitOrder], _ key: String, _ database: Database) throws {
        for (position, order) in orders.enumerated() {
            try database.execute(sql: """
            INSERT INTO buy_order (experiment_id, id, position, ticker, shares, limit_price,
                                   placed_at, expires_at, filled_on, cancelled_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                key, order.id.uuidString, position, order.ticker.symbol, order.shares,
                order.limitPrice.amount.description, StoredValues.stored(order.placedAt),
                StoredValues.stored(order.expiresAt), order.filledOn, order.cancelledAt.map(StoredValues.stored),
            ])
        }
    }

    /// Copies a stored experiment, row for row, under another id.
    static func copy(_ id: ExperimentID, to copy: ExperimentID, in database: Database) throws {
        let source = id.rawValue.uuidString
        let target = copy.rawValue.uuidString
        try database.execute(sql: """
        INSERT INTO experiment (id, cash_balance, name, notes, created_at)
        SELECT ?, cash_balance, name, notes, created_at FROM experiment WHERE id = ?
        """, arguments: [target, source])
        guard database.changesCount > 0 else {
            throw ExperimentRepositoryError.notFound(id)
        }
        for table in childTables {
            let columns = try database.columns(in: table).map(\.name).filter { $0 != "experiment_id" }
            let list = columns.joined(separator: ", ")
            try database.execute(sql: """
            INSERT INTO \(table) (experiment_id, \(list))
            SELECT ?, \(list) FROM \(table) WHERE experiment_id = ?
            """, arguments: [target, source])
        }
    }

    /// The `price_source`, `delayed` and `session_date` columns.
    private struct SourceColumns {
        let source: String
        var delayed: Bool?
        var sessionDate: String?
    }

    private static func columns(of source: PriceSource) -> SourceColumns {
        switch source {
        case let .liveQuote(delayed): SourceColumns(source: "liveQuote", delayed: delayed)
        case let .close(sessionDate): SourceColumns(source: "close", sessionDate: sessionDate)
        case let .limitOrderFill(sessionDate): SourceColumns(source: "limitOrderFill", sessionDate: sessionDate)
        }
    }

    private static func columns(of source: SalePriceSource) -> SourceColumns {
        switch source {
        case let .liveQuote(delayed): SourceColumns(source: "liveQuote", delayed: delayed)
        case let .close(sessionDate): SourceColumns(source: "close", sessionDate: sessionDate)
        }
    }

    // MARK: Reading

    static func read(header: Row, id: ExperimentID, from database: Database) throws -> Experiment {
        let key = id.rawValue.uuidString
        return try Experiment(
            cashBalance: Money(StoredValues.decimal(header, "cash_balance", what: "cash balance")),
            purchases: rows("purchase", key, database).map(purchase),
            limitOrders: rows("sell_order", key, database).map(sellOrder),
            buyLimitOrders: rows("buy_order", key, database).map(buyOrder),
            sales: rows("sale", key, database).map(sale),
            name: StoredValues.optionalText(header, "name", what: "name"),
            notes: StoredValues.optionalText(header, "notes", what: "notes"),
            createdAt: StoredValues.optionalDate(header, "created_at", what: "created date"),
        )
    }

    private static func rows(_ table: String, _ key: String, _ database: Database) throws -> [Row] {
        try Row.fetchAll(
            database,
            sql: "SELECT * FROM \(table) WHERE experiment_id = ? ORDER BY position",
            arguments: [key],
        )
    }

    private static func purchase(_ row: Row) throws -> Purchase {
        try Purchase(
            id: StoredValues.uuid(row, "id", what: "purchase id"),
            ticker: ticker(row, what: "purchase ticker"),
            shares: StoredValues.integer(row, "shares", what: "purchase shares"),
            pricePerShare: StoredValues.decimal(row, "price_per_share", what: "purchase price"),
            pricedAt: StoredValues.date(row, "priced_at", what: "purchase date"),
            priceSource: priceSource(row, of: "purchase"),
        )
    }

    private static func sale(_ row: Row) throws -> Sale {
        let source: SalePriceSource
        switch try priceSource(row, of: "sale") {
        case let .liveQuote(delayed): source = .liveQuote(delayed: delayed)
        case let .close(sessionDate): source = .close(sessionDate: sessionDate)
        case .limitOrderFill:
            throw StoredValueError(detail: "sale price source \"limitOrderFill\" isn't recognized")
        }
        return try Sale(
            id: StoredValues.uuid(row, "id", what: "sale id"),
            purchaseID: StoredValues.uuid(row, "purchase_id", what: "sale purchase id"),
            shares: StoredValues.integer(row, "shares", what: "sale shares"),
            pricePerShare: StoredValues.decimal(row, "price_per_share", what: "sale price"),
            soldAt: StoredValues.date(row, "sold_at", what: "sale date"),
            priceSource: source,
        )
    }

    private static func sellOrder(_ row: Row) throws -> LimitOrder {
        try LimitOrder(
            id: StoredValues.uuid(row, "id", what: "sell order id"),
            purchaseID: StoredValues.uuid(row, "purchase_id", what: "sell order purchase id"),
            shares: StoredValues.integer(row, "shares", what: "sell order shares"),
            limitPrice: Money(StoredValues.decimal(row, "limit_price", what: "sell order limit price")),
            placedAt: StoredValues.date(row, "placed_at", what: "sell order placed date"),
            expiresAt: StoredValues.date(row, "expires_at", what: "sell order expiry date"),
            filledOn: StoredValues.optionalText(row, "filled_on", what: "sell order fill session"),
            cancelledAt: StoredValues.optionalDate(row, "cancelled_at", what: "sell order cancelled date"),
        )
    }

    private static func buyOrder(_ row: Row) throws -> BuyLimitOrder {
        try BuyLimitOrder(
            id: StoredValues.uuid(row, "id", what: "buy order id"),
            ticker: ticker(row, what: "buy order ticker"),
            shares: StoredValues.integer(row, "shares", what: "buy order shares"),
            limitPrice: Money(StoredValues.decimal(row, "limit_price", what: "buy order limit price")),
            placedAt: StoredValues.date(row, "placed_at", what: "buy order placed date"),
            expiresAt: StoredValues.date(row, "expires_at", what: "buy order expiry date"),
            filledOn: StoredValues.optionalText(row, "filled_on", what: "buy order fill session"),
            cancelledAt: StoredValues.optionalDate(row, "cancelled_at", what: "buy order cancelled date"),
        )
    }

    private static func ticker(_ row: Row, what: String) throws -> Ticker {
        let symbol = try StoredValues.text(row, "ticker", what: what)
        guard let ticker = try? Ticker(symbol) else {
            throw StoredValueError(detail: "\(what) \"\(symbol)\" isn't valid")
        }
        return ticker
    }

    private static func priceSource(_ row: Row, of kind: String) throws -> PriceSource {
        let source = try StoredValues.text(row, "price_source", what: "\(kind) price source")
        let delayed = try StoredValues.optionalBool(row, "delayed", what: "\(kind) delayed flag")
        let sessionDate = try StoredValues.optionalText(row, "session_date", what: "\(kind) session date")
        switch (source, delayed, sessionDate) {
        case let ("liveQuote", delayed?, _): return .liveQuote(delayed: delayed)
        case let ("close", _, sessionDate?): return .close(sessionDate: sessionDate)
        case let ("limitOrderFill", _, sessionDate?): return .limitOrderFill(sessionDate: sessionDate)
        default: throw StoredValueError(detail: "\(kind) price source \"\(source)\" isn't recognized")
        }
    }
}
