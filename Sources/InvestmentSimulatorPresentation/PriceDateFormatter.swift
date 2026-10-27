import Foundation
import InvestmentSimulatorCore

/// Words for when a price is from. A close or a limit order fill is dated
/// by its New York session, so it reads as the same day wherever the user is; a live quote
/// shows the user's own time.
public struct PriceDateFormatter {
    private static let marketTimeZone = TimeZone(identifier: "America/New_York")!

    private let timeZone: TimeZone
    private let locale: Locale

    public init(timeZone: TimeZone = .current, locale: Locale = .current) {
        self.timeZone = timeZone
        self.locale = locale
    }

    /// The day a price is from, such as "Oct 23, 2026".
    public func day(of date: Date, source: PriceSource) -> String {
        date.formatted(style(date: .abbreviated, time: .omitted, source: source))
    }

    /// A New York session's day, such as "Oct 23, 2026" for `2026-10-23`.
    /// Text that isn't a `yyyy-MM-dd` date comes back as it is.
    public func day(ofSession sessionDate: String) -> String {
        let parts = sessionDate.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.marketTimeZone
        // Noon, so no daylight saving change moves it to another day.
        guard parts.count == 3,
              let noon = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        else {
            return sessionDate
        }
        return noon.formatted(style(date: .abbreviated, time: .omitted, source: .close(sessionDate: sessionDate)))
    }

    /// Where a quote's price came from and when.
    public func label(for quote: Quote) -> String {
        let when = quote.asOf.formatted(style(date: .abbreviated, time: .shortened, source: quote.source))
        return switch quote.source {
        case .liveQuote(delayed: true):
            "15-minute delayed quote, \(when)"
        case .liveQuote(delayed: false):
            "Live quote, \(when)"
        case .close:
            "Close on \(day(of: quote.asOf, source: quote.source))"
        case .limitOrderFill:
            "Limit order filled on \(day(of: quote.asOf, source: quote.source))"
        }
    }

    private func style(
        date: Date.FormatStyle.DateStyle,
        time: Date.FormatStyle.TimeStyle,
        source: PriceSource,
    ) -> Date.FormatStyle {
        let zone = switch source {
        case .close, .limitOrderFill: Self.marketTimeZone
        case .liveQuote: timeZone
        }
        return Date.FormatStyle(date: date, time: time, locale: locale, timeZone: zone)
    }
}
