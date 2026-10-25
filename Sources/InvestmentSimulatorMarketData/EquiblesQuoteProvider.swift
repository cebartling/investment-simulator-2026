import Foundation
import InvestmentSimulatorCore

/// Prices a ticker from Equibles (ADR-0012): the live quote when the plan
/// includes it and it is current, otherwise the latest settled close.
public struct EquiblesQuoteProvider: QuoteProviding {
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

    public func quote(for ticker: Ticker) async throws(QuoteError) -> Quote {
        // Read on every request, so a key saved in Settings works at once.
        let key = try apiKey()
        let (status, data) = try await get(
            baseURL.appending(path: "stocks/\(ticker.symbol)/quote"),
            key: key,
        )
        switch status {
        case 200:
            let live = try decode(LiveQuoteResponse.self, from: data)
            // A stale quote predates the current session; never show it as
            // the current price.
            if !live.stale {
                return try Quote(
                    ticker: ticker,
                    price: decimal(from: live.price),
                    asOf: date(fromTimestamp: live.asOf),
                    source: .liveQuote(delayed: live.delayed),
                )
            }
        case 403:
            // The plan covers end-of-day data only.
            break
        default:
            throw error(for: status, ticker: ticker)
        }
        return try await latestClose(for: ticker, key: key)
    }

    private func latestClose(for ticker: Ticker, key: String) async throws(QuoteError) -> Quote {
        let url = baseURL.appending(path: "prices/latest")
            .appending(queryItems: [URLQueryItem(name: "tickers", value: ticker.symbol)])
        let (status, data) = try await get(url, key: key)
        guard status == 200 else {
            throw error(for: status, ticker: ticker)
        }
        let response = try decode(LatestClosesResponse.self, from: data)
        guard let row = response.data.first(where: { $0.ticker == ticker.symbol }) else {
            throw .unknownTicker(ticker)
        }
        return try Quote(
            ticker: ticker,
            price: decimal(from: row.close),
            asOf: closeTime(onSession: row.date),
            source: .close(sessionDate: row.date),
        )
    }

    private func apiKey() throws(QuoteError) -> String {
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

    private func get(_ url: URL, key: String) async throws(QuoteError) -> (Int, Data) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await transport.get(request)
            return (response.statusCode, data)
        } catch {
            throw .unavailable("Couldn't reach Equibles.")
        }
    }

    private func error(for status: Int, ticker: Ticker) -> QuoteError {
        switch status {
        case 401: .invalidAPIKey
        case 404: .unknownTicker(ticker)
        case 429: .dailyLimitReached
        default: .unavailable("Equibles answered with HTTP \(status).")
        }
    }

    private func decode<T: Decodable>(_: T.Type, from data: Data) throws(QuoteError) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw .unreadableResponse
        }
    }

    /// `JSONDecoder` reads JSON numbers as `Double`. `String(Double)` is the
    /// shortest text that reads back as the same `Double`, so a price sent
    /// with a few decimal places comes back exactly (ADR-0012).
    private func decimal(from price: Double) throws(QuoteError) -> Decimal {
        guard let decimal = Decimal(string: String(price), locale: Locale(identifier: "en_US_POSIX")) else {
            throw .unreadableResponse
        }
        return decimal
    }

    private func date(fromTimestamp text: String) throws(QuoteError) -> Date {
        let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
        guard let date else {
            throw .unreadableResponse
        }
        return date
    }

    /// US markets close at 4 PM New York time.
    private func closeTime(onSession sessionDate: String) throws(QuoteError) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let parts = sessionDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 16))
        else {
            throw .unreadableResponse
        }
        return date
    }
}

private extension QuoteError {
    static let unreadableResponse = QuoteError.unavailable("Equibles sent a response the app couldn't read.")
}

private struct LiveQuoteResponse: Decodable {
    let price: Double
    let asOf: String
    let stale: Bool
    let delayed: Bool
}

private struct LatestClosesResponse: Decodable {
    struct Row: Decodable {
        let ticker: String
        let date: String
        let close: Double
    }

    let data: [Row]
}

/// Core doesn't format display strings, so the adapter describes the
/// errors it raises.
extension QuoteError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your Equibles API key in Settings to get prices."
        case .invalidAPIKey:
            "Equibles didn't accept the API key. Check it in Settings."
        case let .unknownTicker(ticker):
            "Equibles has no price for \(ticker.symbol)."
        case .dailyLimitReached:
            "You've reached today's Equibles request limit. It resets at midnight UTC."
        case let .unavailable(detail):
            "Couldn't get a price. \(detail)"
        }
    }
}
