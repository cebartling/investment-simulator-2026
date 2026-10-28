import Foundation
import InvestmentSimulatorCore

public enum ExperimentCodingError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidCashBalance(String)
    case invalidTicker(String)
    case invalidPrice(String)
    case invalidDate(String)
    case invalidPriceSource(String)
    case invalidLimitPrice(String)
    case invalidOrderDate(String)
    case invalidCreatedDate(String)
    case invalidSalePrice(String)
    case invalidSaleDate(String)
    case invalidSalePriceSource(String)
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
        case let .invalidCreatedDate(date):
            "The experiment's created date \"\(date)\" isn't a valid date."
        case let .invalidSalePrice(price):
            "A sale's price \"\(price)\" isn't a valid amount."
        case let .invalidSaleDate(date):
            "A sale's date \"\(date)\" isn't a valid date."
        case let .invalidSalePriceSource(source):
            "A sale's price source \"\(source)\" isn't recognized."
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
            "A limit order or sale sells shares of a purchase the experiment doesn't have."
        case .insufficientShares:
            "A limit order or sale sells more shares than the purchase has free."
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
            "Two purchases, orders or sales share an ID."
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

/// Domain errors a sale in a file can trigger.
extension SaleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .nonPositiveShares:
            "A sale must be for at least one share."
        case .nonPositivePrice:
            "A sale's price must be more than zero."
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
