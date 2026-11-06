import Foundation

/// How far a quote's price is from the previous session's close (PIN-511).
public struct PriceChange: Sendable, Hashable {
    /// Per share, unrounded like a quoted price. Negative for a fall.
    public let amount: Decimal
    /// The amount as a percent of the previous close, unrounded, such as
    /// 2.5 for 2.5%.
    public let percent: Decimal
}

public extension Quote {
    /// The change from the close of the latest session in `bars` before the
    /// quote's session: the day before during and after trading, whether or
    /// not that day's bar has posted. Nil when `bars` has no earlier session.
    func change(since bars: [DailyBar]) -> PriceChange? {
        let session = sessionDate
        guard let previous = bars.filter({ $0.sessionDate < session }).max(by: { $0.sessionDate < $1.sessionDate })
        else {
            return nil
        }
        // A bar's close is positive, since its low is.
        let amount = price - previous.close
        return PriceChange(amount: amount, percent: amount / previous.close * 100)
    }
}
