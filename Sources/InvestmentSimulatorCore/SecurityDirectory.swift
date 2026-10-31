import Foundation

/// A security in the directory of listed tickers.
public struct ListedSecurity: Sendable, Hashable {
    public let ticker: Ticker
    /// As the directory spells it, which can be all capitals.
    public let name: String
    public let exchange: String?

    public init(ticker: Ticker, name: String, exchange: String?) {
        self.ticker = ticker
        self.name = name
        self.exchange = exchange
    }
}

/// Driven port for finding listed securities (ADR-0019). `async` because
/// adapters reach the network (ADR-0003).
public protocol SecurityDirectory: Sendable {
    /// The best matches for a name or symbol, best first.
    func search(_ text: String) async throws(MarketDataError) -> [ListedSecurity]
    /// The listed security for `ticker`, or nil if the directory lacks it.
    func security(for ticker: Ticker) async throws(MarketDataError) -> ListedSecurity?
}

public extension [ListedSecurity] {
    /// Matches on a name or symbol, ignoring case and the spelling of a share
    /// class. Ranked exact symbol, symbol prefix, name prefix, name contains,
    /// keeping this list's order within a rank.
    func matching(_ text: String) -> [ListedSecurity] {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !name.isEmpty else {
            return []
        }
        let symbol = Self.comparableSymbol(name)
        var ranks: [[ListedSecurity]] = [[], [], [], []]
        for security in self {
            let listedSymbol = Self.comparableSymbol(security.ticker.symbol)
            let listedName = security.name.uppercased()
            if listedSymbol == symbol {
                ranks[0].append(security)
            } else if listedSymbol.hasPrefix(symbol) {
                ranks[1].append(security)
            } else if listedName.hasPrefix(name) {
                ranks[2].append(security)
            } else if listedName.contains(name) {
                ranks[3].append(security)
            }
        }
        return Array(ranks.joined().prefix(Self.matchLimit))
    }

    /// The row for `ticker`, however its share class is spelled: `BRK.B` is
    /// listed as `BRK-B`.
    func security(for ticker: Ticker) -> ListedSecurity? {
        let symbol = Self.comparableSymbol(ticker.symbol)
        return first { Self.comparableSymbol($0.ticker.symbol) == symbol }
    }

    private static var matchLimit: Int {
        20
    }

    private static func comparableSymbol(_ symbol: String) -> String {
        symbol.replacing(".", with: "-")
    }
}
