import Foundation
import InvestmentSimulatorCore
import Observation

/// Drives the Buy sheet: pick a ticker and shares, get a price, then buy
/// with the experiment's cash.
@Observable
public final class PurchaseModel {
    public enum PriceState: Equatable {
        case none
        case loading
        case priced(Quote)
        case failed(String)
    }

    public var tickerText = "" {
        didSet {
            if tickerText != oldValue {
                priceState = .none
                needsAPIKey = false
            }
        }
    }

    public var shares = 1
    public private(set) var priceState = PriceState.none
    /// True when the last price failed for want of a working API key.
    public private(set) var needsAPIKey = false
    public let availableCash: Money

    private let quotes: any QuoteProviding
    private let purchaseID: UUID

    /// `purchaseID` identifies the purchase this sheet makes.
    public init(availableCash: Money, quotes: any QuoteProviding, purchaseID: UUID = UUID()) {
        self.availableCash = availableCash
        self.quotes = quotes
        self.purchaseID = purchaseID
    }

    private var ticker: Ticker? {
        try? Ticker(tickerText)
    }

    public var tickerMessage: String? {
        tickerText.isEmpty || ticker != nil ? nil : "Enter a ticker symbol, such as VTI."
    }

    public var sharesMessage: String? {
        shares > 0 ? nil : "Buy at least one share."
    }

    public var canGetPrice: Bool {
        ticker != nil && priceState != .loading
    }

    public func getPrice() async {
        guard let ticker else {
            return
        }
        let requestedText = tickerText
        priceState = .loading
        needsAPIKey = false
        do throws(QuoteError) {
            let quote = try await quotes.quote(for: ticker)
            // The ticker changed while waiting; this price is for another one.
            guard tickerText == requestedText else {
                return
            }
            priceState = .priced(quote)
        } catch {
            guard tickerText == requestedText else {
                return
            }
            priceState = .failed(error.localizedDescription)
            needsAPIKey = error == .missingAPIKey || error == .invalidAPIKey
        }
    }

    /// The purchase the current price and shares would make.
    private var pendingPurchase: Purchase? {
        guard case let .priced(quote) = priceState else {
            return nil
        }
        return try? Purchase(
            id: purchaseID,
            ticker: quote.ticker,
            shares: shares,
            pricePerShare: quote.price,
            pricedAt: quote.asOf,
            priceSource: quote.source,
        )
    }

    public var cost: Money? {
        pendingPurchase?.cost
    }

    public var remainingCash: Money? {
        cost.map { availableCash - $0 }
    }

    public var shortfallMessage: String? {
        guard let cost, cost > availableCash else {
            return nil
        }
        return "That costs more than the cash balance."
    }

    public var canBuy: Bool {
        guard let cost else {
            return false
        }
        return cost <= availableCash
    }

    /// The purchase to make, or nil while it can't be bought.
    public func buy() -> Purchase? {
        canBuy ? pendingPurchase : nil
    }
}
