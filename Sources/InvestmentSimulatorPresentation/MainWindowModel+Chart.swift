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
    /// ranges it loaded survive switching panes.
    func priceChart(of ticker: Ticker) -> PriceChartModel {
        if let chart = priceCharts[ticker] {
            return chart
        }
        let chart = PriceChartModel(ticker: ticker, dailyPrices: dailyPrices, clock: clock)
        priceCharts[ticker] = chart
        return chart
    }

    /// Charts `range` for `ticker`, replacing a range still loading.
    @discardableResult
    func showRange(_ range: PriceRange, of ticker: Ticker) -> Task<Void, Never> {
        let chart = priceChart(of: ticker)
        chartTasks[ticker]?.cancel()
        let task = Task { await chart.showRange(range) }
        chartTasks[ticker] = task
        return task
    }

    /// The trades of `ticker` placed on its chart's axis in `timeZone`,
    /// leaving out those before the range it shows.
    func chartTrades(of ticker: Ticker, in timeZone: TimeZone) -> [TradeMark.Plotted] {
        let sessions = priceChart(of: ticker).range.sessions(endingAt: clock())
        return TradeMark.plot(tradeMarks(of: ticker), in: timeZone, within: sessions)
    }
}
