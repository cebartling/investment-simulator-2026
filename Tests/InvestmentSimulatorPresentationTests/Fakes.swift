import Foundation
import InvestmentSimulatorCore
import Synchronization
import Testing

/// Answers every quote request with `result`.
final class FakeQuotes: QuoteProviding {
    private let result: Mutex<Result<Quote, QuoteError>>
    private let count = Mutex(0)

    init(_ result: Result<Quote, QuoteError>) {
        self.result = Mutex(result)
    }

    var requestCount: Int {
        count.withLock { $0 }
    }

    func answer(with newResult: Result<Quote, QuoteError>) {
        result.withLock { $0 = newResult }
    }

    func quote(for _: Ticker) async throws(QuoteError) -> Quote {
        count.withLock { $0 += 1 }
        return try result.withLock { $0 }.get()
    }
}

/// Answers each ticker's daily bars from `bars`, or every request with
/// `failure`, and records the requests it was sent.
final class FakeDailyPrices: DailyPriceProviding {
    struct Request: Equatable {
        let ticker: String
        let startDate: String
        let endDate: String
    }

    private let bars: [String: [DailyBar]]
    private let failure: QuoteError?
    private let sent = Mutex<[Request]>([])

    init(_ bars: [String: [DailyBar]] = [:], failure: QuoteError? = nil) {
        self.bars = bars
        self.failure = failure
    }

    var requests: [Request] {
        sent.withLock { $0 }
    }

    func dailyBars(
        for ticker: Ticker,
        from startDate: String,
        through endDate: String,
    ) async throws(QuoteError) -> [DailyBar] {
        sent.withLock { $0.append(Request(ticker: ticker.symbol, startDate: startDate, endDate: endDate)) }
        if let failure {
            throw failure
        }
        return bars[ticker.symbol] ?? []
    }
}

/// A bar for `session` whose high is `high`, with the low, open and close at 1.
func makeDailyBar(session: String, high: Decimal) throws -> DailyBar {
    try DailyBar(sessionDate: session, open: 1, high: high, low: 1, close: 1)
}

final class FakeCredentials: CredentialStoring {
    struct StoreError: Error {}

    private let key: Mutex<String?>
    private let failsToSave: Bool
    private let reads = Mutex(0)

    init(_ key: String? = nil, failsToSave: Bool = false) {
        self.key = Mutex(key)
        self.failsToSave = failsToSave
    }

    /// How many times the secret itself was read.
    var keyReadCount: Int {
        reads.withLock { $0 }
    }

    func apiKey() throws -> String? {
        reads.withLock { $0 += 1 }
        return key.withLock { $0 }
    }

    func hasAPIKey() throws -> Bool {
        key.withLock { $0 != nil }
    }

    func setAPIKey(_ newKey: String?) throws {
        if failsToSave {
            throw StoreError()
        }
        key.withLock { $0 = newKey }
    }
}

func makeQuote(price: String, source: PriceSource = .liveQuote(delayed: true)) throws -> Quote {
    try Quote(
        ticker: Ticker("VTI"),
        price: #require(Decimal(string: price)),
        asOf: Date(timeIntervalSince1970: 1_793_000_000),
        source: source,
    )
}

let fixedPurchaseID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
