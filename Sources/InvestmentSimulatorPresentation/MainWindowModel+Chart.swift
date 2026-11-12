import Foundation
import InvestmentSimulatorCore

/// A stock card's Chart pane (PIN-515): the ticker's closes, with its trades
/// marked on them.
public extension MainWindowModel {
    /// The trades of `ticker`: each purchase, including buy limit fills and
    /// purchases sold since, then each market sale, then each filled sell
    /// order. An order that hasn't filled isn't a trade, so it isn't marked.
    func tradeMarks(of ticker: Ticker) -> [TradeMark] {
        let purchases = purchases(of: ticker)
        let purchaseIDs = Set(purchases.map(\.id))
        let buys = purchases.map {
            TradeMark(id: $0.id, side: .buy, sessionDate: $0.sessionDate, price: $0.pricePerShare)
        }
        let sales = experiment.sales.filter { purchaseIDs.contains($0.purchaseID) }.map {
            TradeMark(id: $0.id, side: .sell, sessionDate: $0.sessionDate, price: $0.pricePerShare)
        }
        let fills = experiment.limitOrders.compactMap { order -> TradeMark? in
            guard purchaseIDs.contains(order.purchaseID), let filledOn = order.filledOn else {
                return nil
            }
            return TradeMark(id: order.id, side: .sell, sessionDate: filledOn, price: order.limitPrice.amount)
        }
        return buys + sales + fills
    }

    /// The chart of `ticker`'s Chart pane: the same one every time, so the
    /// ranges it loaded that day survive switching panes.
    func priceChart(of ticker: Ticker) -> PriceChartModel {
        if let chart = priceCharts[ticker] {
            return chart
        }
        let chart = PriceChartModel(ticker: ticker, dailyPrices: dailyPrices, clock: clock)
        priceCharts[ticker] = chart
        return chart
    }

    /// Charts `range` for `ticker`, replacing a range still loading. Ranges
    /// loaded on an earlier New York day are asked for again (PIN-519), as
    /// `loadLatestSession(of:)` asks again for the Overview's sessions.
    @discardableResult
    func showRange(_ range: PriceRange, of ticker: Ticker) -> Task<Void, Never> {
        let chart = priceChart(of: ticker)
        let today = range.sessions(endingAt: clock()).upperBound
        if chartDays[ticker] != today {
            chart.forgetRanges()
            chartDays[ticker] = today
        }
        return chart.load(range)
    }

    /// Charts the range `ticker`'s chart shows, as its pane appears: from
    /// memory once loaded that day and since the last `refreshPrices()`, and
    /// without asking again while it loads. A failed range is asked for again.
    @discardableResult
    func showChart(of ticker: Ticker) -> Task<Void, Never> {
        let chart = priceChart(of: ticker)
        return chart.loadInProgress ?? showRange(chart.range, of: ticker)
    }

    /// Refresh Prices: quotes again what `HoldingsPricesModel.refreshPrices(holding:)`
    /// does, and has each card's chart ask again (PIN-519), at once if its
    /// Chart pane shows, else the next time it shows.
    func refreshPrices() async {
        for chart in priceCharts.values {
            chart.forgetRanges()
        }
        let showing = priceCharts.keys.filter { expandedTickers.contains($0) && selectedPane(for: $0) == .chart }
        let reloads = showing.map { showRange(priceChart(of: $0).range, of: $0) }
        await holdingsPrices.refreshPrices(holding: experiment.heldTickers)
        for reload in reloads {
            await reload.value
        }
    }

    /// The trades of `ticker` placed on its chart's axis in `timeZone`,
    /// leaving out those before the bars it shows, none while it loads or
    /// failed. Bars loaded on an earlier day start before today's range does
    /// (PIN-520), and a trade made since still shows past the last close.
    func chartTrades(of ticker: Ticker, in timeZone: TimeZone) -> [TradeMark.Plotted] {
        let chart = priceChart(of: ticker)
        guard let shown = chart.shownSessions else {
            return []
        }
        let today = chart.range.sessions(endingAt: clock()).upperBound
        // The later of the two, so a clock set back can't end before the start.
        let sessions = shown.lowerBound ... max(shown.upperBound, today)
        return TradeMark.plot(tradeMarks(of: ticker), in: timeZone, within: sessions)
    }
}
