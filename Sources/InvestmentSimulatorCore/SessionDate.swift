import Foundation

/// Turns a market session's `yyyy-MM-dd` date into an instant on that day in
/// one time zone. Holds one `Calendar`, so mapping a whole chart builds one.
public nonisolated struct SessionDateParser: Sendable {
    /// New York, the market's time zone.
    public static let marketTimeZone = TimeZone(identifier: "America/New_York")!
    public static let market = SessionDateParser(timeZone: marketTimeZone)

    private let calendar: Calendar

    public init(timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// `hour` o'clock on the session `sessionDate` (`yyyy-MM-dd`) in the
    /// parser's zone, or nil if the text isn't a real calendar date.
    public func date(of sessionDate: String, hour: Int) -> Date? {
        guard sessionDate.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil else {
            return nil
        }
        let parts = sessionDate.split(separator: "-").compactMap { Int($0) }
        let day = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        // A Gregorian calendar rolls 2026-02-30 over to March, so read the
        // date back to be sure it's the one that was written.
        guard let date = calendar.date(from: day),
              calendar.dateComponents([.year, .month, .day], from: date) == day
        else {
            return nil
        }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)
    }
}

/// The Gregorian calendar in New York, the market's time zone.
let marketCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = SessionDateParser.marketTimeZone
    return calendar
}()

/// True for a real market session date written `yyyy-MM-dd`, which sorts as text.
func isSessionDate(_ text: String) -> Bool {
    SessionDateParser.market.date(of: text, hour: 12) != nil
}

/// The `yyyy-MM-dd` date in New York at `date`.
func sessionDate(at date: Date) -> String {
    let day = marketCalendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", day.year!, day.month!, day.day!)
}

/// 4 PM in New York on the session `sessionDate` (`yyyy-MM-dd`), when the
/// market closes, or nil if it isn't such a date.
func sessionClose(on sessionDate: String) -> Date? {
    SessionDateParser.market.date(of: sessionDate, hour: 16)
}
