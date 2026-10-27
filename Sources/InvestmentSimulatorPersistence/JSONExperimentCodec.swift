import Foundation
import InvestmentSimulatorCore

/// Maps an `Experiment` to and from the versioned `.invsim` JSON format.
/// Writes the latest version; reads every version, migrating older ones.
public struct JSONExperimentCodec: ExperimentCoding {
    public init() {}

    private static let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    public func encode(_ experiment: Experiment) throws -> Data {
        let document = ExperimentDocumentV5(
            schemaVersion: ExperimentDocumentV5.schemaVersion,
            cashBalance: experiment.cashBalance.amount.description,
            purchases: experiment.purchases.map(encode),
            limitOrders: experiment.limitOrders.map(encode),
            buyLimitOrders: experiment.buyLimitOrders.map(encode),
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
            return try Experiment(cashBalance: cashBalance(from: document.cashBalance))
        case ExperimentDocumentV2.schemaVersion:
            // Migration: version 2 predates limit orders.
            let document = try decoder.decode(ExperimentDocumentV2.self, from: data)
            return try Experiment(
                cashBalance: cashBalance(from: document.cashBalance),
                purchases: document.purchases.map(decode),
            )
        case ExperimentDocumentV3.schemaVersion:
            // Migration: version 3 predates fills, so its orders are unfilled.
            let document = try decoder.decode(ExperimentDocumentV3.self, from: data)
            return try Experiment(
                cashBalance: cashBalance(from: document.cashBalance),
                purchases: document.purchases.map(decode),
                limitOrders: document.limitOrders.map(\.unfilled.uncancelled).map(decode),
            )
        case ExperimentDocumentV4.schemaVersion:
            // Migration: version 4 predates buy orders and cancellations.
            let document = try decoder.decode(ExperimentDocumentV4.self, from: data)
            return try Experiment(
                cashBalance: cashBalance(from: document.cashBalance),
                purchases: document.purchases.map(decode),
                limitOrders: document.limitOrders.map(\.uncancelled).map(decode),
            )
        case ExperimentDocumentV5.schemaVersion:
            let document = try decoder.decode(ExperimentDocumentV5.self, from: data)
            return try Experiment(
                cashBalance: cashBalance(from: document.cashBalance),
                purchases: document.purchases.map(decode),
                limitOrders: document.limitOrders.map(decode),
                buyLimitOrders: document.buyLimitOrders.map(decode),
            )
        default:
            throw ExperimentCodingError.unsupportedSchemaVersion(version)
        }
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

public enum ExperimentCodingError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidCashBalance(String)
    case invalidTicker(String)
    case invalidPrice(String)
    case invalidDate(String)
    case invalidPriceSource(String)
    case invalidLimitPrice(String)
    case invalidOrderDate(String)
}

/// Shown by the document system when a file can't be opened.
extension ExperimentCodingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            "The experiment uses file format version \(version), which this version of Investment Simulator can't read."
        case let .invalidCashBalance(cashBalance):
            "The experiment's cash balance \"\(cashBalance)\" isn't a valid amount."
        case let .invalidTicker(ticker):
            "A purchase's ticker \"\(ticker)\" isn't a valid symbol."
        case let .invalidPrice(price):
            "A purchase's price \"\(price)\" isn't a valid amount."
        case let .invalidDate(date):
            "A purchase's date \"\(date)\" isn't a valid date."
        case let .invalidPriceSource(source):
            "A purchase's price source \"\(source)\" isn't recognized."
        case let .invalidLimitPrice(price):
            "A limit order's price \"\(price)\" isn't a valid amount."
        case let .invalidOrderDate(date):
            "A limit order's date \"\(date)\" isn't a valid date."
        }
    }

    public var failureReason: String? {
        errorDescription
    }
}

/// Core doesn't format display strings (ADR-0002), so the adapter that
/// reads files describes the domain errors a file can trigger.
extension ExperimentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .negativeCashBalance:
            "The experiment's cash balance can't be negative."
        case .insufficientCash:
            "The purchase costs more than the experiment's available cash."
        case .unknownPurchase:
            "A limit order sells shares of a purchase the experiment doesn't have."
        case .insufficientShares:
            "A limit order sells more shares than the purchase has free."
        case .unknownOrder:
            "The experiment has no such limit order."
        case .orderAlreadyFilled:
            "The limit order has already filled."
        case .orderCancelled:
            "The limit order was cancelled."
        case .orderNotOpen:
            "The limit order is no longer open."
        case .mismatchedFillPurchase:
            "A buy limit order's fill doesn't match the experiment's purchases."
        case .duplicateID:
            "Two purchases or orders share an ID."
        case .invalidSessionDate:
            "A limit order's fill date must be written yyyy-MM-dd."
        }
    }

    public var failureReason: String? {
        errorDescription
    }
}

/// Domain errors a purchase in a file can trigger.
extension PurchaseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .nonPositiveShares:
            "A purchase must be for at least one share."
        case .nonPositivePrice:
            "A purchase's price must be more than zero."
        }
    }

    public var failureReason: String? {
        errorDescription
    }
}

/// Domain errors a limit order in a file can trigger.
extension LimitOrderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .nonPositiveShares:
            "A limit order must be for at least one share."
        case .nonPositivePrice:
            "A limit order's price must be more than zero."
        case .negativeProfitPercent:
            "A limit order's profit can't be negative."
        case .invalidSessionDate:
            "A limit order's fill date must be written yyyy-MM-dd."
        case .filledAndCancelled:
            "A limit order can't be both filled and cancelled."
        }
    }

    public var failureReason: String? {
        errorDescription
    }
}
