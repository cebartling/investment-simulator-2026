import Foundation

public extension Experiment {
    /// The experiment with each unfilled order filled in the first session of
    /// `bars` whose high reaches its limit price. Only settled sessions after
    /// the one the order was placed in, and before the date it expires, can
    /// fill it: a daily bar doesn't say when in the session its high came, so
    /// the placement session is skipped (ADR-0013). `now` decides which
    /// session is still trading and isn't settled.
    func fillingLimitOrders(from bars: [Ticker: [DailyBar]], at now: Date) throws(ExperimentError) -> Experiment {
        let today = sessionDate(at: now)
        let tickers = Dictionary(uniqueKeysWithValues: purchases.map { ($0.id, $0.ticker) })
        var experiment = self
        for order in limitOrders where order.filledOn == nil {
            guard let ticker = tickers[order.purchaseID], let tickerBars = bars[ticker] else {
                continue
            }
            let placed = sessionDate(at: order.placedAt)
            let expires = sessionDate(at: order.expiresAt)
            let fillingBar = tickerBars
                .filter { $0.sessionDate > placed && $0.sessionDate < min(expires, today) }
                .sorted { $0.sessionDate < $1.sessionDate }
                .first { $0.high >= order.limitPrice.amount }
            if let fillingBar {
                experiment = try experiment.filling(orderID: order.id, on: fillingBar.sessionDate)
            }
        }
        return experiment
    }
}
