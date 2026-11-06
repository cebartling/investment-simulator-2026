import Foundation
import InvestmentSimulatorCore

/// The stock cards (PIN-510).
public extension MainWindowModel {
    /// A card for each ticker bought, or with an order row showing at
    /// `date`, by symbol. A ticker whose only orders expired or were
    /// cancelled, and never filled, has a card only while those orders show.
    func stockCards(at date: Date) -> [StockCard] {
        let tickers = Set(experiment.purchases.map(\.ticker)).union(limitOrderRows(at: date).map(\.ticker))
        return tickers
            .sorted { $0.symbol < $1.symbol }
            .map {
                StockCard(
                    ticker: $0,
                    heldShares: experiment.heldShares(of: $0),
                    averagePrice: experiment.averagePrice(of: $0),
                )
            }
    }

    /// Opens the card of `ticker` if it is closed, else closes it. Other
    /// cards stay as they are.
    func toggleExpansion(of ticker: Ticker) {
        if expandedTickers.remove(ticker) == nil {
            expandedTickers.insert(ticker)
        }
    }

    /// The pane the card of `ticker` shows: Overview until another is chosen.
    func selectedPane(for ticker: Ticker) -> StockPane {
        selectedPanes[ticker] ?? .overview
    }

    func selectPane(_ pane: StockPane, for ticker: Ticker) {
        selectedPanes[ticker] = pane
    }

    /// The purchases of `ticker`, in the order they were made.
    func purchases(of ticker: Ticker) -> [Purchase] {
        experiment.purchases.filter { $0.ticker == ticker }
    }

    /// The sale rows of `ticker`, by when they sold.
    func saleRows(of ticker: Ticker) -> [SaleRow] {
        saleRows.filter { $0.ticker == ticker }
    }

    /// The order rows of `ticker` as they stand at `date`, as
    /// `limitOrderRows(at:)` shows them.
    func limitOrderRows(of ticker: Ticker, at date: Date) -> [LimitOrderRow] {
        limitOrderRows(at: date).filter { $0.ticker == ticker }
    }

    /// Loads the latest settled session of `ticker` in the past month into
    /// `latestSessions`, for its card's Overview. Loads once; a failure is
    /// asked for again the next time the Overview shows. Daily bars are
    /// settled sessions, so during trading this is an earlier day's. A live
    /// quote is to replace it (PIN-511).
    func loadLatestSession(of ticker: Ticker) async {
        switch latestSessions[ticker] {
        case .loading, .loaded, .empty:
            return
        case .failed, nil:
            break
        }
        latestSessions[ticker] = .loading
        let sessions = PriceRange.oneMonth.sessions(endingAt: clock())
        do throws(QuoteError) {
            let bars = try await dailyPrices.dailyBars(
                for: ticker,
                from: sessions.lowerBound,
                through: sessions.upperBound,
            )
            latestSessions[ticker] = bars.max { $0.sessionDate < $1.sessionDate }.map { .loaded($0) } ?? .empty
        } catch .unknownTicker {
            latestSessions[ticker] = .empty
        } catch {
            latestSessions[ticker] = .failed(error.localizedDescription)
        }
    }

    /// Loads the company name of `ticker` into `companyNames` the first
    /// time it is asked for, as each card appears. Until then, and when it
    /// can't load, the card shows the ticker alone. A ticker with no profile
    /// isn't asked for again; any other failure, such as a missing API key,
    /// is, the next time the card appears.
    func loadCompanyName(of ticker: Ticker) async {
        guard companyNameRequests.insert(ticker).inserted else {
            return
        }
        do throws(MarketDataError) {
            companyNames[ticker] = try await profiles.companyProfile(for: ticker).name
        } catch .noData {
            // No name to show, now or later.
        } catch {
            companyNameRequests.remove(ticker)
        }
    }
}
