import Foundation

/// How far back a price history chart reaches (PIN-416). Equibles' history
/// starts in 2020-01, so five years is the longest range that fills.
public enum PriceRange: CaseIterable, Sendable {
    case oneMonth
    case sixMonths
    case oneYear
    case fiveYears

    /// Five years of daily bars would take three requests; weekly bars
    /// take one (ADR-0019).
    public var interval: BarInterval {
        self == .fiveYears ? .weekly : .daily
    }

    /// The sessions from this range's start through today, both
    /// `yyyy-MM-dd` in New York, for `dailyBars(for:from:through:interval:)`.
    public func sessions(endingAt now: Date) -> ClosedRange<String> {
        let start = marketCalendar.date(byAdding: .month, value: -months, to: now)!
        return sessionDate(at: start) ... sessionDate(at: now)
    }

    private var months: Int {
        switch self {
        case .oneMonth: 1
        case .sixMonths: 6
        case .oneYear: 12
        case .fiveYears: 60
        }
    }
}
