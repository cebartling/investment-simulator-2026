import Foundation
import InvestmentSimulatorCore

/// Words for when a price is from. A close or a limit order fill is dated
/// by its New York session, so it reads as the same day wherever the user is; a live quote
/// shows the user's own time.
public struct PriceDateFormatter {
    private static let marketTimeZone = SessionDateParser.marketTimeZone

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
        // Noon, so no daylight saving change moves it to another day.
        guard let noon = SessionDateParser.market.date(of: sessionDate, hour: 12) else {
            return sessionDate
        }
        return noon.formatted(style(date: .abbreviated, time: .omitted, source: .close(sessionDate: sessionDate)))
    }

    /// The New York day at `date`, such as "Oct 23, 2026", so a timestamp
    /// reads as the same day wherever the user is.
    public func marketDay(of date: Date) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: Self.marketTimeZone)
        return date.formatted(style)
    }

    /// When a trade at `date` was priced, for the stock cards' tables
    /// (PIN-512): a live quote's day and time in the user's time zone, such
    /// as "Oct 23, 2026 at 10:31 AM", so two trades on one day read apart.
    /// A close or a limit order fill has no time of its own, so it shows
    /// its New York session's day, such as "Oct 23, 2026".
    public func tradeTime(of date: Date, source: PriceSource) -> String {
        switch source {
        case .liveQuote:
            date.formatted(style(date: .abbreviated, time: .shortened, source: source))
        case .close, .limitOrderFill:
            day(of: date, source: source)
        }
    }

    /// When a market sale was priced, as `tradeTime(of:source:)` shows a
    /// purchase. A sale at a live quote shows its quote's time, `quotedAt`,
    /// or `soldAt` for a sale made before quote times were recorded
    /// (ADR-0026). A sale at a close shows the close's session, such as
    /// "Oct 23, 2026", not `soldAt`, which can be days later.
    public func tradeTime(ofSaleAt soldAt: Date, quotedAt: Date?, source: SalePriceSource) -> String {
        switch source {
        case let .liveQuote(delayed):
            tradeTime(of: quotedAt ?? soldAt, source: .liveQuote(delayed: delayed))
        case let .close(sessionDate):
            day(ofSession: sessionDate)
        }
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
