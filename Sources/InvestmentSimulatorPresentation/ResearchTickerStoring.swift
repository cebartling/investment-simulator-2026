import Foundation

/// The Research window's open tickers, as the symbols a quit leaves behind
/// (ADR-0019). Nothing else is kept; prices and research reload at launch.
public struct SavedResearchTickers: Equatable {
    public var symbols: [String]
    public var selected: String?

    public init(symbols: [String], selected: String?) {
        self.symbols = symbols
        self.selected = selected
    }
}

/// Where the open tickers are kept between launches. Tests use an in-memory
/// fake (ADR-0007).
public protocol ResearchTickerStoring {
    func load() -> SavedResearchTickers
    func save(_ tickers: SavedResearchTickers)
}

/// Keeps nothing, so tickers aren't restored.
public struct NoResearchTickerStore: ResearchTickerStoring {
    public init() {}

    public func load() -> SavedResearchTickers {
        SavedResearchTickers(symbols: [], selected: nil)
    }

    public func save(_: SavedResearchTickers) {}
}
