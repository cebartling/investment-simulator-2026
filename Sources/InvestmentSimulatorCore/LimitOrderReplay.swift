import Foundation

public extension Experiment {
    /// The experiment with each order open at `now` filled in the first
    /// session of `bars` whose high reaches its limit price. Only settled
    /// sessions after the one the order was placed in can fill it: a daily
    /// bar doesn't say when in the session its high came, so the placement
    /// session is skipped, and today's session, still trading, is too
    /// (ADR-0013). An open order hasn't reached its expiry date, so every
    /// such session is before it expired.
    ///
    /// An order that expired unfilled is left alone. Its shares are free
    /// again and may already be sold by a later order.
    func fillingLimitOrders(from bars: [Ticker: [DailyBar]], at now: Date) throws(ExperimentError) -> Experiment {
        let today = sessionDate(at: now)
        let tickers = Dictionary(uniqueKeysWithValues: purchases.map { ($0.id, $0.ticker) })
        var experiment = self
        for order in limitOrders where order.isOpen(at: now) {
            guard let ticker = tickers[order.purchaseID], let tickerBars = bars[ticker] else {
                continue
            }
            let placed = sessionDate(at: order.placedAt)
            let fillingBar = tickerBars
                .filter { $0.sessionDate > placed && $0.sessionDate < today }
                .sorted { $0.sessionDate < $1.sessionDate }
                .first { $0.high >= order.limitPrice.amount }
            if let fillingBar {
                experiment = try experiment.filling(orderID: order.id, on: fillingBar.sessionDate)
            }
        }
        return experiment
    }

    /// For each ticker with an order open at `now` that a settled session
    /// could fill, the sessions to fetch bars for: from the earliest such
    /// order's placement through today. The sessions at both ends can't fill
    /// an order; they keep the range simple, and
    /// `fillingLimitOrders(from:at:)` skips them.
    func sessionsToReplay(at now: Date) -> [Ticker: ClosedRange<String>] {
        let today = sessionDate(at: now)
        let tickers = Dictionary(uniqueKeysWithValues: purchases.map { ($0.id, $0.ticker) })
        var ranges: [Ticker: ClosedRange<String>] = [:]
        for order in limitOrders where order.isOpen(at: now) {
            guard let ticker = tickers[order.purchaseID] else {
                continue
            }
            let placed = sessionDate(at: order.placedAt)
            guard placed < today else {
                continue
            }
            ranges[ticker] = ranges[ticker].map { min($0.lowerBound, placed) ... today } ?? placed ... today
        }
        return ranges
    }
}
