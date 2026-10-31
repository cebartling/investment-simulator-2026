import Foundation

/// One SEC filing on a ticker.
public struct Filing: Sendable, Hashable {
    /// As the SEC names it, such as `10-K`.
    public let form: String
    /// `yyyy-MM-dd`, which sorts as text.
    public let filedDate: String
    /// `yyyy-MM-dd`.
    public let reportingForDate: String?
    public let url: URL

    public init(form: String, filedDate: String, reportingForDate: String?, url: URL) throws(FilingError) {
        guard isSessionDate(filedDate) else {
            throw .invalidDate(filedDate)
        }
        if let reportingForDate, !isSessionDate(reportingForDate) {
            throw .invalidDate(reportingForDate)
        }
        self.form = form
        self.filedDate = filedDate
        self.reportingForDate = reportingForDate
        self.url = url
    }
}

public enum FilingError: Error, Equatable {
    case invalidDate(String)
}

/// Driven port for a ticker's recent SEC filings (ADR-0019). `async` because
/// adapters reach the network (ADR-0003).
public protocol FilingProviding: Sendable {
    func filings(for ticker: Ticker) async throws(MarketDataError) -> [Filing]
}
