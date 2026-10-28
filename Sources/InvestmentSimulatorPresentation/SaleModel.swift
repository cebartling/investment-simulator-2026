import Foundation
import InvestmentSimulatorCore
import Observation

/// Drives the Market Sell sheet: sell free shares of one purchase at a
/// market price, adding the proceeds to the experiment's cash (ADR-0016).
@Observable
public final class SaleModel {
    public enum PriceState: Equatable {
        case none
        case loading
        case priced(Quote)
        case failed(String)
    }

    public var shares: Int
    public private(set) var priceState = PriceState.none
    /// True when the last price failed for want of a working API key.
    public private(set) var needsAPIKey = false

    public let purchase: Purchase
    /// Shares of the purchase neither sold nor in an open sell order.
    public let availableShares: Int
    public let cashBalance: Money

    private let quotes: any QuoteProviding
    private let clock: () -> Date
    private let saleID: UUID

    /// `clock` tells the time; the sale is made when `sell()` is called.
    /// `saleID` identifies it.
    public init(
        purchase: Purchase,
        availableShares: Int,
        cashBalance: Money,
        quotes: any QuoteProviding,
        clock: @escaping () -> Date = Date.init,
        saleID: UUID = UUID(),
    ) {
        self.purchase = purchase
        self.availableShares = availableShares
        self.cashBalance = cashBalance
        self.quotes = quotes
        self.clock = clock
        self.saleID = saleID
        shares = availableShares
    }

    public var sharesMessage: String? {
        if availableShares <= 0 {
            return "No shares of this purchase are free. Cancel an open sell order to free its shares."
        }
        return (1 ... availableShares).contains(shares) ? nil : "Sell between 1 and \(availableShares) shares."
    }

    public var canGetPrice: Bool {
        availableShares > 0 && priceState != .loading
    }

    public func getPrice() async {
        priceState = .loading
        needsAPIKey = false
        do throws(QuoteError) {
            priceState = try await .priced(quotes.quote(for: purchase.ticker))
        } catch {
            priceState = .failed(error.localizedDescription)
            needsAPIKey = error == .missingAPIKey || error == .invalidAPIKey
        }
    }

    /// The sale the current price and shares would make now, or nil while
    /// they can't be sold.
    private var pendingSale: Sale? {
        guard sharesMessage == nil,
              case let .priced(quote) = priceState,
              let source = SalePriceSource(quote.source)
        else {
            return nil
        }
        return try? Sale(
            id: saleID,
            purchaseID: purchase.id,
            shares: shares,
            pricePerShare: quote.price,
            soldAt: clock(),
            priceSource: source,
        )
    }

    public var proceeds: Money? {
        pendingSale?.proceeds
    }

    public var realizedGain: Money? {
        pendingSale?.realizedGain(on: purchase)
    }

    /// The cash balance plus the proceeds. A sale reserves nothing, so it
    /// is the balance, not the available cash.
    public var cashAfter: Money? {
        proceeds.map { cashBalance + $0 }
    }

    public var canSell: Bool {
        pendingSale != nil
    }

    /// The sale to make, or nil while it can't be made.
    public func sell() -> Sale? {
        pendingSale
    }
}
