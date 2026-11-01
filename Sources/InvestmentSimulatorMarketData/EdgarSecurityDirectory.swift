import Foundation
import InvestmentSimulatorCore

/// Serves the ticker directory from SEC EDGAR (ADR-0019). The list downloads
/// once per launch, on first use, and stays in memory. A failed download
/// isn't kept, so the next call tries again and reads the contact email again.
public actor EdgarSecurityDirectory: SecurityDirectory {
    private let transport: any HTTPTransport
    private let contactEmails: any ContactEmailStoring
    private let listURL: URL
    private var securities: [ListedSecurity]?
    /// The download under way, shared by every call that needs the list.
    private var download: Task<Result<[ListedSecurity], MarketDataError>, Never>?

    public init(
        transport: any HTTPTransport,
        contactEmails: any ContactEmailStoring,
        listURL: URL = URL(string: "https://www.sec.gov/files/company_tickers_exchange.json")!,
    ) {
        self.transport = transport
        self.contactEmails = contactEmails
        self.listURL = listURL
    }

    public func search(_ text: String) async throws(MarketDataError) -> [ListedSecurity] {
        try await list().matching(text)
    }

    public func security(for ticker: Ticker) async throws(MarketDataError) -> ListedSecurity? {
        try await list().security(for: ticker)
    }

    private func list() async throws(MarketDataError) -> [ListedSecurity] {
        if let securities {
            return securities
        }
        // Unstructured, so one caller's cancellation can't fail the others.
        let shared = download ?? Task { await finishDownload() }
        download = shared
        return try await shared.value.get()
    }

    private func finishDownload() async -> Result<[ListedSecurity], MarketDataError> {
        defer { download = nil }
        do throws(MarketDataError) {
            let list = try await downloadedList()
            securities = list
            return .success(list)
        } catch {
            return .failure(error)
        }
    }

    private func downloadedList() async throws(MarketDataError) -> [ListedSecurity] {
        var request = URLRequest(url: listURL)
        try request.setValue("Investment Simulator \(savedEmail())", forHTTPHeaderField: "User-Agent")
        let data: Data
        let status: Int
        do {
            let (body, response) = try await transport.get(request)
            data = body
            status = response.statusCode
        } catch {
            throw .unavailable("Couldn't reach SEC EDGAR.")
        }
        guard status == 200 else {
            throw .unavailable("SEC EDGAR answered with HTTP \(status).")
        }
        do {
            return try JSONDecoder().decode(TickerList.self, from: data).securities
        } catch {
            throw .unavailable("SEC EDGAR sent a response the app couldn't read.")
        }
    }

    private func savedEmail() throws(MarketDataError) -> String {
        let email: String?
        do {
            email = try contactEmails.contactEmail()
        } catch {
            throw .unavailable("Couldn't read the SEC contact email: \(error.localizedDescription)")
        }
        guard let email else {
            throw .missingContactEmail
        }
        return email
    }
}

/// `company_tickers_exchange.json`: rows of `[cik, name, ticker, exchange]`.
private struct TickerList: Decodable {
    struct Row: Decodable {
        let name: String?
        let ticker: String?
        let exchange: String?

        init(from decoder: any Decoder) throws {
            var columns = try decoder.unkeyedContainer()
            _ = try columns.decode(Int.self)
            name = try columns.decodeIfPresent(String.self)
            ticker = try columns.decodeIfPresent(String.self)
            exchange = try columns.decodeIfPresent(String.self)
        }
    }

    let data: [Row]

    /// Leaves out rows that can't be opened as a ticker.
    var securities: [ListedSecurity] {
        data.compactMap { row in
            guard let name = row.name, let symbol = row.ticker, let ticker = try? Ticker(symbol) else {
                return nil
            }
            return ListedSecurity(ticker: ticker, name: name, exchange: row.exchange)
        }
    }
}
