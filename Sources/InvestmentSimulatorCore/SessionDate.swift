import Foundation

/// The Gregorian calendar in New York, the market's time zone.
let marketCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

/// True for a market session's date written `yyyy-MM-dd`, which sorts as text.
func isSessionDate(_ text: String) -> Bool {
    text.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil
}

/// The `yyyy-MM-dd` date in New York at `date`.
func sessionDate(at date: Date) -> String {
    let day = marketCalendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", day.year!, day.month!, day.day!)
}

/// 4 PM in New York on the session `sessionDate` (`yyyy-MM-dd`), when the
/// market closes, or nil if it isn't such a date.
func sessionClose(on sessionDate: String) -> Date? {
    guard isSessionDate(sessionDate) else {
        return nil
    }
    let parts = sessionDate.split(separator: "-").compactMap { Int($0) }
    return marketCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 16))
}
