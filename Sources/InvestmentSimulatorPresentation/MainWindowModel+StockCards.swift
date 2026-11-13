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

    /// Loads the settled sessions of `ticker` in the past month into
    /// `latestSessions`, for its card's Overview: the latest, and the one
    /// the quote's change is from (PIN-511). Loads once a day, in New York;
    /// a failure is asked for again the next time the Overview shows. Daily
    /// bars are settled sessions, so during trading the latest is an earlier
    /// day's. The month also becomes the card chart's 1M range (PIN-524).
    func loadLatestSession(of ticker: Ticker) async {
        let sessions = PriceRange.oneMonth.sessions(endingAt: clock())
        switch latestSessions[ticker] {
        case .loading:
            return
        case .loaded, .empty:
            guard latestSessionDays[ticker] != sessions.upperBound else {
                return
            }
        case .failed, nil:
            break
        }
        latestSessions[ticker] = .loading
        latestSessionDays[ticker] = sessions.upperBound
        do throws(QuoteError) {
            let bars = try await dailyPrices.dailyBars(
                for: ticker,
                from: sessions.lowerBound,
                through: sessions.upperBound,
            )
            latestSessions[ticker] = RecentSessions(bars).map { .loaded($0) } ?? .empty
            keepOverviewBars(bars, askedFor: sessions, of: ticker)
        } catch .unknownTicker {
            latestSessions[ticker] = .empty
        } catch {
            latestSessions[ticker] = .failed(error.localizedDescription)
        }
    }

    /// Asks for the quote of `ticker` for its card's Overview (PIN-511) if
    /// no shares are held: a held ticker's quote comes with the holdings',
    /// so asking here too would send a second request. Once asked for, the
    /// ticker stays in Refresh Prices.
    func priceOverview(of ticker: Ticker) async {
        guard experiment.heldShares(of: ticker) == 0 else {
            return
        }
        await holdingsPrices.priceOnDemand(ticker)
    }

    /// Loads the sessions of `ticker` again if they were asked for before
    /// its quote's session, as when Refresh Prices runs the morning after
    /// the Overview opened, so the change can show. Never starts the first
    /// load: that's `loadLatestSession(of:)`'s, and a quote arriving while it
    /// runs mustn't cancel it.
    func reloadSessionsIfStale(of ticker: Ticker) async {
        guard let quote = holdingsPrices.lastGoodQuote(of: ticker),
              let askedOn = latestSessionDays[ticker], askedOn < quote.sessionDate
        else {
            return
        }
        await loadLatestSession(of: ticker)
    }

    /// What the Overview of `ticker`'s card shows (PIN-511), from the quote
    /// `holdingsPrices` holds and the sessions `loadLatestSession(of:)`
    /// loaded. A held ticker's quote is the one the header uses.
    func overview(of ticker: Ticker) -> StockOverview {
        let lastSession = latestSessions[ticker]
        let isHeld = experiment.heldShares(of: ticker) > 0
        guard let quote = holdingsPrices.lastGoodQuote(of: ticker) else {
            return StockOverview(
                price: holdingsPrices.failure(of: ticker).map { .failed($0) } ?? .loading,
                change: nil,
                holding: isHeld ? .unpriced : .notHeld,
                lastSession: lastSession,
            )
        }
        // Sessions asked for before the quote's session, as with the Overview
        // open overnight, can lack the one before it, so the change would be
        // from an older close. It waits for them to load again.
        let sessionsAreCurrent = latestSessionDays[ticker].map { $0 >= quote.sessionDate } ?? false
        var change: PriceChange?
        if case let .loaded(recent) = lastSession, sessionsAreCurrent {
            change = quote.change(since: recent.bars)
        }
        let holding: StockOverview.Holding = isHeld
            ? .priced(
                marketValue: experiment.marketValue(of: ticker, at: quote.price),
                gain: experiment.unrealizedGain(of: ticker, at: quote.price),
            )
            : .notHeld
        return StockOverview(price: .quoted(quote), change: change, holding: holding, lastSession: lastSession)
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
