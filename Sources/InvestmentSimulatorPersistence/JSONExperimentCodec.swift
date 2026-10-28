import Foundation
import InvestmentSimulatorCore

/// Maps an `Experiment` to and from the versioned `.invsim` JSON format.
/// Writes the latest version; reads every version, migrating older ones.
public struct JSONExperimentCodec: ExperimentCoding {
    public init() {}

    private static let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    public func encode(_ experiment: Experiment) throws -> Data {
        let document = ExperimentDocumentV7(
            schemaVersion: ExperimentDocumentV7.schemaVersion,
            cashBalance: experiment.cashBalance.amount.description,
            purchases: experiment.purchases.map(encode),
            limitOrders: experiment.limitOrders.map(encode),
            buyLimitOrders: experiment.buyLimitOrders.map(encode),
            sales: experiment.sales.map(encode),
            name: experiment.name,
            notes: experiment.notes,
            createdAt: experiment.createdAt?.formatted(Self.dateFormat),
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    public func decode(_ data: Data) throws -> Experiment {
        let decoder = JSONDecoder()
        let version = try decoder.decode(SchemaVersionProbe.self, from: data).schemaVersion
        switch version {
        case ExperimentDocumentV1.schemaVersion:
            // Migration: version 1 predates purchases.
            let document = try decoder.decode(ExperimentDocumentV1.self, from: data)
            return try datingFromHistory(Experiment(cashBalance: cashBalance(from: document.cashBalance)))
        case ExperimentDocumentV2.schemaVersion:
            // Migration: version 2 predates limit orders.
            let document = try decoder.decode(ExperimentDocumentV2.self, from: data)
            return try datingFromHistory(Experiment(
                cashBalance: cashBalance(from: document.cashBalance),
                purchases: document.purchases.map(decode),
            ))
        case ExperimentDocumentV3.schemaVersion:
            // Migration: version 3 predates fills, so its orders are unfilled.
            let document = try decoder.decode(ExperimentDocumentV3.self, from: data)
            return try datingFromHistory(Experiment(
                cashBalance: cashBalance(from: document.cashBalance),
                purchases: document.purchases.map(decode),
                limitOrders: document.limitOrders.map(\.unfilled.uncancelled).map(decode),
            ))
        case ExperimentDocumentV4.schemaVersion:
            // Migration: version 4 predates buy orders and cancellations.
            let document = try decoder.decode(ExperimentDocumentV4.self, from: data)
            return try datingFromHistory(Experiment(
                cashBalance: cashBalance(from: document.cashBalance),
                purchases: document.purchases.map(decode),
                limitOrders: document.limitOrders.map(\.uncancelled).map(decode),
            ))
        case ExperimentDocumentV5.schemaVersion:
            // Migration: version 5 predates the name, notes and created date.
            let document = try decoder.decode(ExperimentDocumentV5.self, from: data)
            return try datingFromHistory(Experiment(
                cashBalance: cashBalance(from: document.cashBalance),
                purchases: document.purchases.map(decode),
                limitOrders: document.limitOrders.map(decode),
                buyLimitOrders: document.buyLimitOrders.map(decode),
            ))
        case ExperimentDocumentV6.schemaVersion:
            // Migration: version 6 predates sales.
            return try experiment(from: decoder.decode(ExperimentDocumentV6.self, from: data).withNoSales)
        case ExperimentDocumentV7.schemaVersion:
            return try experiment(from: decoder.decode(ExperimentDocumentV7.self, from: data))
        default:
            throw ExperimentCodingError.unsupportedSchemaVersion(version)
        }
    }

    private func experiment(from document: ExperimentDocumentV7) throws -> Experiment {
        try Experiment(
            cashBalance: cashBalance(from: document.cashBalance),
            purchases: document.purchases.map(decode),
            limitOrders: document.limitOrders.map(decode),
            buyLimitOrders: document.buyLimitOrders.map(decode),
            sales: document.sales.map(decode),
            name: document.name,
            notes: document.notes,
            createdAt: document.createdAt.map(createdDate),
        )
    }

    /// Migration: files before version 6 have no created date, so it is
    /// the earliest purchase or order placement, or nil with neither. A
    /// close-priced purchase carries its session's close, so the date can
    /// be earlier than the experiment really was created.
    private func datingFromHistory(_ experiment: Experiment) throws -> Experiment {
        let dates = experiment.purchases.map(\.pricedAt)
            + experiment.limitOrders.map(\.placedAt)
            + experiment.buyLimitOrders.map(\.placedAt)
        return try Experiment(
            cashBalance: experiment.cashBalance,
            purchases: experiment.purchases,
            limitOrders: experiment.limitOrders,
            buyLimitOrders: experiment.buyLimitOrders,
            createdAt: dates.min(),
        )
    }

    private func encode(_ purchase: Purchase) -> PurchaseV2 {
        var delayed: Bool?
        var sessionDate: String?
        let source: String
        switch purchase.priceSource {
        case let .liveQuote(isDelayed):
            source = "liveQuote"
            delayed = isDelayed
        case let .close(date):
            source = "close"
            sessionDate = date
        case let .limitOrderFill(date):
            source = "limitOrderFill"
            sessionDate = date
        }
        return PurchaseV2(
            id: purchase.id,
            ticker: purchase.ticker.symbol,
            shares: purchase.shares,
            pricePerShare: purchase.pricePerShare.description,
            pricedAt: purchase.pricedAt.formatted(Self.dateFormat),
            priceSource: source,
            delayed: delayed,
            sessionDate: sessionDate,
        )
    }

    private func decode(_ purchase: PurchaseV2) throws -> Purchase {
        guard let ticker = try? Ticker(purchase.ticker) else {
            throw ExperimentCodingError.invalidTicker(purchase.ticker)
        }
        guard let pricedAt = try? Self.dateFormat.parse(purchase.pricedAt) else {
            throw ExperimentCodingError.invalidDate(purchase.pricedAt)
        }
        return try Purchase(
            id: purchase.id,
            ticker: ticker,
            shares: purchase.shares,
            pricePerShare: decimal(from: purchase.pricePerShare, invalid: ExperimentCodingError.invalidPrice),
            pricedAt: pricedAt,
            priceSource: priceSource(of: purchase),
        )
    }

    private func priceSource(of purchase: PurchaseV2) throws -> PriceSource {
        switch (purchase.priceSource, purchase.delayed, purchase.sessionDate) {
        case let ("liveQuote", delayed?, _):
            .liveQuote(delayed: delayed)
        case let ("close", _, sessionDate?):
            .close(sessionDate: sessionDate)
        case let ("limitOrderFill", _, sessionDate?):
            .limitOrderFill(sessionDate: sessionDate)
        default:
            throw ExperimentCodingError.invalidPriceSource(purchase.priceSource)
        }
    }

    private func encode(_ order: LimitOrder) -> LimitOrderV5 {
        LimitOrderV5(
            id: order.id,
            purchaseID: order.purchaseID,
            shares: order.shares,
            limitPrice: order.limitPrice.amount.description,
            placedAt: order.placedAt.formatted(Self.dateFormat),
            expiresAt: order.expiresAt.formatted(Self.dateFormat),
            filledOn: order.filledOn,
            cancelledAt: order.cancelledAt?.formatted(Self.dateFormat),
        )
    }

    private func decode(_ order: LimitOrderV5) throws -> LimitOrder {
        try LimitOrder(
            id: order.id,
            purchaseID: order.purchaseID,
            shares: order.shares,
            limitPrice: limitPrice(from: order.limitPrice),
            placedAt: orderDate(from: order.placedAt),
            expiresAt: orderDate(from: order.expiresAt),
            filledOn: order.filledOn,
            cancelledAt: order.cancelledAt.map(orderDate),
        )
    }

    private func encode(_ order: BuyLimitOrder) -> BuyLimitOrderV5 {
        BuyLimitOrderV5(
            id: order.id,
            ticker: order.ticker.symbol,
            shares: order.shares,
            limitPrice: order.limitPrice.amount.description,
            placedAt: order.placedAt.formatted(Self.dateFormat),
            expiresAt: order.expiresAt.formatted(Self.dateFormat),
            filledOn: order.filledOn,
            cancelledAt: order.cancelledAt?.formatted(Self.dateFormat),
        )
    }

    private func decode(_ order: BuyLimitOrderV5) throws -> BuyLimitOrder {
        guard let ticker = try? Ticker(order.ticker) else {
            throw ExperimentCodingError.invalidTicker(order.ticker)
        }
        return try BuyLimitOrder(
            id: order.id,
            ticker: ticker,
            shares: order.shares,
            limitPrice: limitPrice(from: order.limitPrice),
            placedAt: orderDate(from: order.placedAt),
            expiresAt: orderDate(from: order.expiresAt),
            filledOn: order.filledOn,
            cancelledAt: order.cancelledAt.map(orderDate),
        )
    }

    private func orderDate(from string: String) throws -> Date {
        guard let date = try? Self.dateFormat.parse(string) else {
            throw ExperimentCodingError.invalidOrderDate(string)
        }
        return date
    }

    private func createdDate(from string: String) throws -> Date {
        guard let date = try? Self.dateFormat.parse(string) else {
            throw ExperimentCodingError.invalidCreatedDate(string)
        }
        return date
    }

    private func limitPrice(from string: String) throws -> Money {
        try Money(decimal(from: string, invalid: ExperimentCodingError.invalidLimitPrice))
    }

    private func cashBalance(from string: String) throws -> Money {
        try Money(decimal(from: string, invalid: ExperimentCodingError.invalidCashBalance))
    }

    /// `Decimal` holds at most 38 significant digits.
    private static let maxSignificantDigits = 38

    /// `Decimal(string:)` accepts a numeric prefix ("12abc" is 12) and
    /// silently rounds past 38 significant digits, so the whole string is
    /// checked against a plain decimal pattern and the digit limit first.
    private func decimal(
        from string: String,
        invalid: (String) -> ExperimentCodingError,
    ) throws -> Decimal {
        guard let match = string.wholeMatch(of: /-?0*([0-9]+(?:\.[0-9]+)?)/),
              significantDigits(in: match.1) <= Self.maxSignificantDigits,
              let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
        else {
            throw invalid(string)
        }
        return value
    }

    /// Digits between the first and last nonzero digit; zeros outside them
    /// only move the exponent.
    private func significantDigits(in digits: Substring) -> Int {
        let digits = digits.filter(\.isNumber)
        guard let first = digits.firstIndex(where: { $0 != "0" }),
              let last = digits.lastIndex(where: { $0 != "0" })
        else {
            return 0
        }
        return digits.distance(from: first, to: last) + 1
    }
}

/// Market sales (ADR-0016).
extension JSONExperimentCodec {
    private func encode(_ sale: Sale) -> SaleV7 {
        var delayed: Bool?
        var sessionDate: String?
        let source: String
        switch sale.priceSource {
        case let .liveQuote(isDelayed):
            source = "liveQuote"
            delayed = isDelayed
        case let .close(date):
            source = "close"
            sessionDate = date
        }
        return SaleV7(
            id: sale.id,
            purchaseID: sale.purchaseID,
            shares: sale.shares,
            pricePerShare: sale.pricePerShare.description,
            soldAt: sale.soldAt.formatted(Self.dateFormat),
            priceSource: source,
            delayed: delayed,
            sessionDate: sessionDate,
        )
    }

    private func decode(_ sale: SaleV7) throws -> Sale {
        guard let soldAt = try? Self.dateFormat.parse(sale.soldAt) else {
            throw ExperimentCodingError.invalidSaleDate(sale.soldAt)
        }
        return try Sale(
            id: sale.id,
            purchaseID: sale.purchaseID,
            shares: sale.shares,
            pricePerShare: decimal(from: sale.pricePerShare, invalid: ExperimentCodingError.invalidSalePrice),
            soldAt: soldAt,
            priceSource: priceSource(of: sale),
        )
    }

    private func priceSource(of sale: SaleV7) throws -> SalePriceSource {
        switch (sale.priceSource, sale.delayed, sale.sessionDate) {
        case let ("liveQuote", delayed?, _):
            .liveQuote(delayed: delayed)
        case let ("close", _, sessionDate?):
            .close(sessionDate: sessionDate)
        default:
            throw ExperimentCodingError.invalidSalePriceSource(sale.priceSource)
        }
    }
}
