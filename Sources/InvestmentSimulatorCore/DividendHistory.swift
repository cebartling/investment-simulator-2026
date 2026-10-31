import Foundation

/// A ticker's dividends on one day: those paid so far, those declared for
/// later, and what the last twelve months paid.
public struct DividendHistory: Sendable, Hashable {
    /// Ex-dates after today in New York, newest first.
    public let declared: [Dividend]
    /// Ex-dates through today in New York, newest first.
    public let paid: [Dividend]
    /// The USD paid in the twelve months through today, or nil if those
    /// months held only other currencies. Quotes are in USD, so other
    /// currencies stay out of the sum.
    public let trailingAmountPerShare: Decimal?

    public init(dividends: [Dividend], asOf now: Date) {
        let today = sessionDate(at: now)
        let yearAgo = sessionDate(at: marketCalendar.date(byAdding: .month, value: -12, to: now)!)
        let newestFirst = dividends.sorted { $0.exDate > $1.exDate }
        declared = newestFirst.filter { $0.exDate > today }
        paid = newestFirst.filter { $0.exDate <= today }
        // A year ago today stays out, or ex-dates that repeat on the same
        // date would count five quarters.
        let trailing = paid.filter { $0.exDate > yearAgo }
        let usd = trailing.filter { $0.currency == "USD" }
        trailingAmountPerShare = usd.isEmpty && !trailing.isEmpty
            ? nil
            : usd.reduce(0) { $0 + $1.amountPerShare }
    }

    /// The trailing amount as a fraction of `price`, or nil if there's no
    /// amount or `price` isn't positive.
    public func trailingYield(atPrice price: Decimal) -> Decimal? {
        guard let trailingAmountPerShare, price > 0 else {
            return nil
        }
        return trailingAmountPerShare / price
    }
}
