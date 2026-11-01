import Foundation
import InvestmentSimulatorPresentation

/// Keeps the Research window's open ticker symbols in `UserDefaults` (ADR-0019).
/// Symbols aren't secrets, and nothing else about a ticker is saved.
struct UserDefaultsResearchTickerStore: ResearchTickerStoring {
    private let defaults: UserDefaults
    private let symbolsKey = "research.openTickers"
    private let selectedKey = "research.selectedTicker"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SavedResearchTickers {
        SavedResearchTickers(
            symbols: defaults.stringArray(forKey: symbolsKey) ?? [],
            selected: defaults.string(forKey: selectedKey),
        )
    }

    func save(_ tickers: SavedResearchTickers) {
        defaults.set(tickers.symbols, forKey: symbolsKey)
        defaults.set(tickers.selected, forKey: selectedKey)
    }
}
