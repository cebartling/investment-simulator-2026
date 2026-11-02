import GRDB

/// The database's versioned schema (ADR-0021). Money is TEXT, a decimal
/// string, never REAL or INTEGER (ADR-0002). Dates are REAL seconds since
/// the reference date, which round-trip exactly.
/// `position` keeps each list in the order it was made. A filled buy order
/// and its purchase share an id, so every id is only unique per experiment.
enum ExperimentSchema {
    private static let experimentTable = """
    CREATE TABLE experiment (
                    id TEXT NOT NULL PRIMARY KEY,
                    cash_balance TEXT NOT NULL,
                    name TEXT,
                    notes TEXT,
                    created_at REAL
                );
    """

    private static let purchaseTable = """
    CREATE TABLE purchase (
                    experiment_id TEXT NOT NULL REFERENCES experiment (id) ON DELETE CASCADE,
                    id TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    ticker TEXT NOT NULL,
                    shares INTEGER NOT NULL,
                    price_per_share TEXT NOT NULL,
                    priced_at REAL NOT NULL,
                    price_source TEXT NOT NULL,
                    delayed INTEGER,
                    session_date TEXT,
                    PRIMARY KEY (experiment_id, id)
                );
    """

    private static let saleTable = """
    CREATE TABLE sale (
                    experiment_id TEXT NOT NULL REFERENCES experiment (id) ON DELETE CASCADE,
                    id TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    purchase_id TEXT NOT NULL,
                    shares INTEGER NOT NULL,
                    price_per_share TEXT NOT NULL,
                    sold_at REAL NOT NULL,
                    price_source TEXT NOT NULL,
                    delayed INTEGER,
                    session_date TEXT,
                    PRIMARY KEY (experiment_id, id)
                );
    """

    private static let sellOrderTable = """
    CREATE TABLE sell_order (
                    experiment_id TEXT NOT NULL REFERENCES experiment (id) ON DELETE CASCADE,
                    id TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    purchase_id TEXT NOT NULL,
                    shares INTEGER NOT NULL,
                    limit_price TEXT NOT NULL,
                    placed_at REAL NOT NULL,
                    expires_at REAL NOT NULL,
                    filled_on TEXT,
                    cancelled_at REAL,
                    PRIMARY KEY (experiment_id, id)
                );
    """

    private static let buyOrderTable = """
    CREATE TABLE buy_order (
                    experiment_id TEXT NOT NULL REFERENCES experiment (id) ON DELETE CASCADE,
                    id TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    ticker TEXT NOT NULL,
                    shares INTEGER NOT NULL,
                    limit_price TEXT NOT NULL,
                    placed_at REAL NOT NULL,
                    expires_at REAL NOT NULL,
                    filled_on TEXT,
                    cancelled_at REAL,
                    PRIMARY KEY (experiment_id, id)
                );
    """

    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { database in
            for table in [experimentTable, purchaseTable, saleTable, sellOrderTable, buyOrderTable] {
                try database.execute(sql: table)
            }
        }
        return migrator
    }
}
