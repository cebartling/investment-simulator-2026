import Foundation
import InvestmentSimulatorCore

/// Serves the Research window's sections from Equibles (ADR-0019). A `404`
/// means no data: the tab's quote has already validated the ticker, and
/// Equibles answers the same way for an unknown ticker and for one with
/// nothing to show.
public struct EquiblesResearchProvider: CompanyProfileProviding, ValuationMultiplesProviding, DividendProviding {
    /// Enough for a weekly payer's year and its declared dividends, in one
    /// request. The default page of 20 isn't.
    private static let dividendLimit = 60
    /// Equibles mixes transcripts and proxies in with the filings, and takes
    /// one `documentType` per request, so one page is filtered here instead
    /// of three requests.
    private static let filingLimit = 50
    private static let filingTypes: Set<String> = ["TenK", "TenQ", "EightK"]

    private let transport: any HTTPTransport
    private let credentials: any CredentialStoring
    private let baseURL: URL

    public init(
        transport: any HTTPTransport,
        credentials: any CredentialStoring,
        baseURL: URL = URL(string: "https://api.equibles.com/v1")!,
    ) {
        self.transport = transport
        self.credentials = credentials
        self.baseURL = baseURL
    }

    public func companyProfile(for ticker: Ticker) async throws(MarketDataError) -> CompanyProfile {
        let url = baseURL.appending(path: "screener/stocks")
            .appending(queryItems: [URLQueryItem(name: "tickers", value: ticker.symbol)])
        let response = try await get(ScreenerResponse.self, from: url)
        // An unknown ticker is a 200 with no row. Any row is this ticker's,
        // though not always spelled alike: `BRK.B` comes back as `BRK-B`.
        guard let row = response.data.first else {
            throw .noData
        }
        return try CompanyProfile(
            name: row.name,
            sector: row.sector,
            industry: row.industry,
            marketCap: decimal(from: row.marketCap).map(Money.init),
        )
    }

    public func valuationMultiples(for ticker: Ticker) async throws(MarketDataError) -> ValuationMultiples {
        let url = baseURL.appending(path: "stocks/\(ticker.symbol)/valuation-multiples")
        let response = try await get(ValuationResponse.self, from: url)
        let peers = response.industryContext
        return try ValuationMultiples(
            peRatio: ratio(response.peRatio, peers?.peMedian, peers?.peP25, peers?.peP75),
            evToRevenue: ratio(
                response.evToRevenue,
                peers?.evToRevenueMedian,
                peers?.evToRevenueP25,
                peers?.evToRevenueP75,
            ),
            evToEbit: ratio(response.evToEbit, peers?.evToEbitMedian, peers?.evToEbitP25, peers?.evToEbitP75),
        )
    }

    public func dividends(for ticker: Ticker) async throws(MarketDataError) -> [Dividend] {
        let url = baseURL.appending(path: "stocks/\(ticker.symbol)/dividends")
            .appending(queryItems: [URLQueryItem(name: "limit", value: String(Self.dividendLimit))])
        let response = try await get(DividendsResponse.self, from: url)
        // A stock that pays no dividend is a 200 with no rows.
        guard !response.data.isEmpty else {
            throw .noData
        }
        return try response.data.map { row throws(MarketDataError) in try dividend(from: row) }
    }

    /// Rows come from scraping company sites, so one that can't be read is
    /// left out rather than losing the rest. If none can, that's a failure:
    /// an empty list would read as nothing published.
    public func pressReleases(for ticker: Ticker) async throws(MarketDataError) -> PressReleases {
        let url = baseURL.appending(path: "stocks/\(ticker.symbol)/ir-news")
        let response = try await get(IRNewsResponse.self, from: url)
        let releases = response.data.compactMap(pressRelease(from:))
        guard response.data.isEmpty || !releases.isEmpty else {
            throw .unreadableResponse
        }
        return PressReleases(coverage: coverage(from: response.coverage.status), releases: releases)
    }

    /// As with press releases, a filing that can't be read is left out,
    /// unless that leaves none.
    public func filings(for ticker: Ticker) async throws(MarketDataError) -> [Filing] {
        let url = baseURL.appending(path: "stocks/\(ticker.symbol)/filings")
            .appending(queryItems: [URLQueryItem(name: "limit", value: String(Self.filingLimit))])
        let response = try await get(FilingsResponse.self, from: url)
        let rows = response.data.filter { Self.filingTypes.contains($0.documentType) }
        guard !rows.isEmpty else {
            throw .noData
        }
        let filings = rows.compactMap(filing(from:))
        guard !filings.isEmpty else {
            throw .unreadableResponse
        }
        return filings
    }

    /// Coverage only says how to read an empty list, so a status added later
    /// reads as not covered, not as a failure.
    private func coverage(from status: String) -> PressReleaseCoverage {
        switch status {
        case "scraped": .scraped
        case "attempted": .attempted
        case "discovered": .discovered
        default: .untracked
        }
    }

    private func pressRelease(from row: IRNewsResponse.Row) -> PressRelease? {
        guard let title = row.title, let url = webLink(from: row.url), let text = row.publishedAt,
              let publishedAt = try? Date.ISO8601FormatStyle().parse(text)
        else {
            return nil
        }
        return PressRelease(publishedAt: publishedAt, title: title, url: url, summary: row.summary)
    }

    private func filing(from row: FilingsResponse.Row) -> Filing? {
        guard let form = row.documentTypeName, let filedDate = row.filedDate, let url = webLink(from: row.url) else {
            return nil
        }
        return try? Filing(form: form, filedDate: filedDate, reportingForDate: row.reportingForDate, url: url)
    }

    /// A link the user can click, so nothing but a web page: these come from
    /// a third party and open in the system's handler for their scheme.
    private func webLink(from text: String?) -> URL? {
        guard let text, let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host() != nil
        else {
            return nil
        }
        return url
    }

    private func dividend(from row: DividendsResponse.Row) throws(MarketDataError) -> Dividend {
        let amount = try requiredDecimal(from: row.amountPerShare)
        do {
            return try Dividend(exDate: row.exDate, amountPerShare: amount, currency: row.currency)
        } catch {
            throw .unreadableResponse
        }
    }

    private func ratio(
        _ value: Double?,
        _ median: Double?,
        _ p25: Double?,
        _ p75: Double?,
    ) throws(MarketDataError) -> ValuationRatio {
        try ValuationRatio(
            value: decimal(from: value),
            peerMedian: decimal(from: median),
            peerP25: decimal(from: p25),
            peerP75: decimal(from: p75),
        )
    }

    private func get<T: Decodable>(_: T.Type, from url: URL) async throws(MarketDataError) -> T {
        // Read on every request, so a key saved in Settings works at once.
        let key = try apiKey()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let data: Data
        let status: Int
        do {
            let (body, response) = try await transport.get(request)
            data = body
            status = response.statusCode
        } catch {
            throw .unavailable("Couldn't reach Equibles.")
        }
        switch status {
        case 200: break
        case 401: throw .invalidAPIKey
        case 404: throw .noData
        case 429: throw .dailyLimitReached
        default: throw .unavailable("Equibles answered with HTTP \(status).")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw .unreadableResponse
        }
    }

    private func apiKey() throws(MarketDataError) -> String {
        let key: String?
        do {
            key = try credentials.apiKey()
        } catch {
            throw .unavailable("Couldn't read the API key: \(error.localizedDescription)")
        }
        guard let key, !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw .missingAPIKey
        }
        return key
    }

    /// `JSONDecoder` reads JSON numbers as `Double`. `String(Double)` is the
    /// shortest text that reads back as the same `Double`, so a figure sent
    /// with a few decimal places comes back exactly (ADR-0012).
    private func requiredDecimal(from number: Double) throws(MarketDataError) -> Decimal {
        guard let decimal = Decimal(string: String(number), locale: Locale(identifier: "en_US_POSIX")) else {
            throw .unreadableResponse
        }
        return decimal
    }

    private func decimal(from number: Double?) throws(MarketDataError) -> Decimal? {
        guard let number else {
            return nil
        }
        return try requiredDecimal(from: number)
    }
}

extension EquiblesResearchProvider: PressReleaseProviding, FilingProviding {}

private extension MarketDataError {
    static let unreadableResponse = MarketDataError.unavailable("Equibles sent a response the app couldn't read.")
}

private struct ScreenerResponse: Decodable {
    struct Row: Decodable {
        let name: String
        let sector: String?
        let industry: String?
        let marketCap: Double?
    }

    let data: [Row]
}

private struct ValuationResponse: Decodable {
    struct Peers: Decodable {
        let peMedian: Double?
        let peP25: Double?
        let peP75: Double?
        let evToRevenueMedian: Double?
        let evToRevenueP25: Double?
        let evToRevenueP75: Double?
        let evToEbitMedian: Double?
        let evToEbitP25: Double?
        let evToEbitP75: Double?
    }

    let peRatio: Double?
    let evToRevenue: Double?
    let evToEbit: Double?
    let industryContext: Peers?
}

private struct DividendsResponse: Decodable {
    struct Row: Decodable {
        let exDate: String
        let amountPerShare: Double
        let currency: String
    }

    let data: [Row]
}

private struct IRNewsResponse: Decodable {
    struct Coverage: Decodable {
        let status: String
    }

    /// All optional, so a row with a missing field is left out on its own
    /// and doesn't fail the decoding of the page.
    struct Row: Decodable {
        let publishedAt: String?
        let title: String?
        let url: String?
        let summary: String?
    }

    let coverage: Coverage
    let data: [Row]
}

private struct FilingsResponse: Decodable {
    /// Only `documentType` is required, so a row with a missing field is
    /// left out on its own and doesn't fail the decoding of the page.
    struct Row: Decodable {
        let documentType: String
        let documentTypeName: String?
        let filedDate: String?
        let reportingForDate: String?
        let url: String?
    }

    let data: [Row]
}

/// Core doesn't format display strings, so the adapter describes the
/// errors it raises.
extension MarketDataError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your Equibles API key in Settings to see this."
        case .invalidAPIKey:
            "Equibles didn't accept the API key. Check it in Settings."
        case .dailyLimitReached:
            "You've reached today's Equibles request limit. It resets at midnight UTC."
        case let .unavailable(detail):
            "Couldn't load this. \(detail)"
        case .noData:
            "Equibles has no data for this ticker."
        }
    }
}
