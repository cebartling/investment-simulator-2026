import Foundation

public extension Experiment {
    /// The experiment with each order open at `now` filled in the first
    /// session of `bars` that reaches its limit price: a high at or above it
    /// for a sell order, a low at or below it for a buy order (ADR-0014).
    /// Only settled
    /// sessions after the one the order was placed in can fill it: a daily
    /// bar doesn't say when in the session its high came, so the placement
    /// session is skipped, and today's session, still trading, is too
    /// (ADR-0013). An open order hasn't reached its expiry date, so every
    /// such session is before it expired.
    ///
    /// An order that expired or was cancelled unfilled is left alone. Its
    /// shares or cash are free again and may already be spent.
    func fillingLimitOrders(from bars: [Ticker: [DailyBar]], at now: Date) throws(ExperimentError) -> Experiment {
        let tickers = Dictionary(uniqueKeysWithValues: purchases.map { ($0.id, $0.ticker) })
        var experiment = self
        for order in limitOrders where order.isOpen(at: now) {
            guard let ticker = tickers[order.purchaseID] else {
                continue
            }
            let fillingBar = Self.eligibleBars(bars[ticker] ?? [], placedAt: order.placedAt, now: now)
                .first { $0.high >= order.limitPrice.amount }
            if let fillingBar {
                experiment = try experiment.filling(orderID: order.id, on: fillingBar.sessionDate)
            }
        }
        for order in buyLimitOrders where order.isOpen(at: now) {
            let fillingBar = Self.eligibleBars(bars[order.ticker] ?? [], placedAt: order.placedAt, now: now)
                .first { $0.low <= order.limitPrice.amount }
            if let fillingBar {
                experiment = try experiment.fillingBuyOrder(orderID: order.id, on: fillingBar.sessionDate)
            }
        }
        return experiment
    }

    /// The bars of settled sessions after the one an order placed at
    /// `placedAt` was placed in, in session order.
    private static func eligibleBars(_ bars: [DailyBar], placedAt: Date, now: Date) -> [DailyBar] {
        let placed = sessionDate(at: placedAt)
        let today = sessionDate(at: now)
        return bars
            .filter { $0.sessionDate > placed && $0.sessionDate < today }
            .sorted { $0.sessionDate < $1.sessionDate }
    }

    /// For each ticker with a sell or buy order open at `now` that a settled session
    /// could fill, the sessions to fetch bars for: from the earliest such
    /// order's placement through today. The sessions at both ends can't fill
    /// an order; they keep the range simple, and
    /// `fillingLimitOrders(from:at:)` skips them.
    func sessionsToReplay(at now: Date) -> [Ticker: ClosedRange<String>] {
        let today = sessionDate(at: now)
        let tickers = Dictionary(uniqueKeysWithValues: purchases.map { ($0.id, $0.ticker) })
        let sellOrders = limitOrders
            .filter { $0.isOpen(at: now) }
            .compactMap { order in tickers[order.purchaseID].map { ($0, order.placedAt) } }
        let buyOrders = buyLimitOrders
            .filter { $0.isOpen(at: now) }
            .map { ($0.ticker, $0.placedAt) }
        var ranges: [Ticker: ClosedRange<String>] = [:]
        for (ticker, placedAt) in sellOrders + buyOrders {
            let placed = sessionDate(at: placedAt)
            guard placed < today else {
                continue
            }
            ranges[ticker] = ranges[ticker].map { min($0.lowerBound, placed) ... today } ?? placed ... today
        }
        return ranges
    }
}
