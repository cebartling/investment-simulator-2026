import Foundation

/// One SEC filing on a ticker.
public struct Filing: Sendable, Hashable {
    /// As the SEC names it, such as `10-K`.
    public let form: String
    /// `yyyy-MM-dd`, which sorts as text.
    public let filedDate: String
    /// `yyyy-MM-dd`.
    public let reportingForDate: String?
    /// Dashed, such as `0000320193-26-000020`. Nil when the source has none.
    public let accessionNumber: String?
    /// The filing's page on Equibles.
    public let url: URL

    public init(
        form: String,
        filedDate: String,
        reportingForDate: String?,
        accessionNumber: String?,
        url: URL,
    ) throws(FilingError) {
        guard isSessionDate(filedDate) else {
            throw .invalidDate(filedDate)
        }
        if let reportingForDate, !isSessionDate(reportingForDate) {
            throw .invalidDate(reportingForDate)
        }
        self.form = form
        self.filedDate = filedDate
        self.reportingForDate = reportingForDate
        self.accessionNumber = accessionNumber
        self.url = url
    }

    /// The filing's folder on sec.gov, or nil without an accession number.
    /// `cik` comes from the directory, not the accession: the accession's
    /// prefix is the filing agent's ID for many filings.
    public func secURL(cik: Int) -> URL? {
        guard let accessionNumber, !accessionNumber.isEmpty else {
            return nil
        }
        let folder = accessionNumber.replacingOccurrences(of: "-", with: "")
        return URL(string: "https://www.sec.gov/Archives/edgar/data/\(cik)/\(folder)/")
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
