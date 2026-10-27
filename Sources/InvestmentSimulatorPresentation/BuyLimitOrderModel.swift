import Foundation
import InvestmentSimulatorCore
import Observation

/// Drives the Buy Limit sheet: a buy limit order on a ticker, at a typed
/// limit price that a quote can prefill, paid from the available cash.
@Observable
public final class BuyLimitOrderModel {
    public enum QuoteState: Equatable {
        case none
        case loading
        case quoted(Quote)
        case failed(String)
    }

    public var tickerText = "" {
        didSet {
            if tickerText != oldValue {
                quoteState = .none
                needsAPIKey = false
            }
        }
    }

    public var shares = 1
    /// Typed, or prefilled by Get Quote.
    public var enteredPrice: Decimal = 0
    public private(set) var quoteState = QuoteState.none
    /// True when the last quote failed for want of a working API key.
    public private(set) var needsAPIKey = false
    /// The cash not already reserved by open buy orders.
    public let availableCash: Money

    private let quotes: any QuoteProviding
    private let clock: () -> Date
    private let orderID: UUID

    /// `clock` tells the time; the order is placed when `place()` is
    /// called. `orderID` identifies it.
    public init(
        availableCash: Money,
        quotes: any QuoteProviding,
        clock: @escaping () -> Date = Date.init,
        orderID: UUID = UUID(),
    ) {
        self.availableCash = availableCash
        self.quotes = quotes
        self.clock = clock
        self.orderID = orderID
    }

    private var ticker: Ticker? {
        try? Ticker(tickerText)
    }

    public var tickerMessage: String? {
        tickerText.isEmpty || ticker != nil ? nil : "Enter a ticker symbol, such as VTI."
    }

    public var canGetQuote: Bool {
        ticker != nil && quoteState != .loading
    }

    /// Prefills the limit price with the ticker's current price, rounded to
    /// cents. A failed quote leaves the typed price alone.
    public func getQuote() async {
        guard let ticker else {
            return
        }
        let requestedText = tickerText
        quoteState = .loading
        needsAPIKey = false
        do throws(QuoteError) {
            let quote = try await quotes.quote(for: ticker)
            // The ticker changed while waiting; this price is for another one.
            guard tickerText == requestedText else {
                return
            }
            quoteState = .quoted(quote)
            enteredPrice = Money(quote.price).roundedToCents().amount
        } catch {
            guard tickerText == requestedText else {
                return
            }
            quoteState = .failed(error.localizedDescription)
            needsAPIKey = error == .missingAPIKey || error == .invalidAPIKey
        }
    }

    /// The typed price in whole cents, normalized with banker's rounding
    /// (ADR-0002), or nil unless it is above zero.
    public var limitPrice: Money? {
        let rounded = Money(enteredPrice).roundedToCents()
        return rounded > .zero ? rounded : nil
    }

    public var priceMessage: String? {
        limitPrice == nil ? "Enter a limit price above zero." : nil
    }

    public var sharesMessage: String? {
        shares > 0 ? nil : "Buy at least one share."
    }

    /// What the order reserves: the limit price times the shares, rounded to
    /// cents. Nil while either is invalid.
    public var cost: Money? {
        guard sharesMessage == nil, let limitPrice else {
            return nil
        }
        return limitPrice.times(shares).roundedToCents()
    }

    public var shortfallMessage: String? {
        guard let cost, cost > availableCash else {
            return nil
        }
        return "That costs more than the available cash."
    }

    /// When the order would expire if it were placed now.
    public var expiresAt: Date {
        LimitOrder.expiry(forPlacedAt: clock())
    }

    public var canPlace: Bool {
        guard ticker != nil, let cost else {
            return false
        }
        return cost <= availableCash
    }

    /// The order to place, or nil while the input is invalid.
    public func place() -> BuyLimitOrder? {
        guard canPlace, let ticker, let limitPrice else {
            return nil
        }
        do {
            return try BuyLimitOrder.placed(
                id: orderID,
                ticker: ticker,
                shares: shares,
                limitPrice: limitPrice,
                at: clock(),
            )
        } catch {
            preconditionFailure("canPlace allowed an invalid buy limit order: \(error)")
        }
    }
}
