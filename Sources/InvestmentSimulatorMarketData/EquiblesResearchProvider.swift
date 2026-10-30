import Foundation
import InvestmentSimulatorCore

/// Serves the Research window's sections from Equibles (ADR-0019). A `404`
/// means no data: the tab's quote has already validated the ticker, and
/// Equibles answers the same way for an unknown ticker and for one with
/// nothing to show.
public struct EquiblesResearchProvider: CompanyProfileProviding, ValuationMultiplesProviding {
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
    private func decimal(from number: Double?) throws(MarketDataError) -> Decimal? {
        guard let number else {
            return nil
        }
        guard let decimal = Decimal(string: String(number), locale: Locale(identifier: "en_US_POSIX")) else {
            throw .unreadableResponse
        }
        return decimal
    }
}

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
