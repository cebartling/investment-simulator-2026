import Foundation
import InvestmentSimulatorCore
import Observation

/// One open ticker in the Research window (ADR-0019): its quote, and later
/// one state per section.
@Observable
public final class ResearchTabModel: Identifiable {
    public enum QuoteState: Equatable {
        case loading
        case quoted(Quote)
        case failed(QuoteError)
    }

    public let ticker: Ticker
    public private(set) var quoteState = QuoteState.loading

    private let quotes: any QuoteProviding

    public init(ticker: Ticker, quotes: any QuoteProviding) {
        self.ticker = ticker
        self.quotes = quotes
    }

    public var id: Ticker {
        ticker
    }

    /// True when the quote failed for want of a working API key.
    public var needsAPIKey: Bool {
        quoteState == .failed(.missingAPIKey) || quoteState == .failed(.invalidAPIKey)
    }

    /// Quotes the ticker again. A cancelled request changes nothing more: the
    /// ticker was closed, or a newer refresh took over.
    public func refresh() async {
        quoteState = .loading
        do throws(QuoteError) {
            let quote = try await quotes.quote(for: ticker)
            guard !Task.isCancelled else {
                return
            }
            quoteState = .quoted(quote)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            quoteState = .failed(error)
        }
    }
}
