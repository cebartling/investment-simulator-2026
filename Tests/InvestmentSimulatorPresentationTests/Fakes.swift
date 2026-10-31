import Foundation
import InvestmentSimulatorCore
import Synchronization
import Testing

/// Answers every quote request with `result`. `whileAnswering` runs on the
/// main actor during each request, as a change made while it waits.
final class FakeQuotes: QuoteProviding {
    private let result: Mutex<Result<Quote, QuoteError>>
    private let count = Mutex(0)
    private let hook = Mutex<(@MainActor @Sendable () -> Void)?>(nil)

    init(_ result: Result<Quote, QuoteError>) {
        self.result = Mutex(result)
    }

    var requestCount: Int {
        count.withLock { $0 }
    }

    func answer(with newResult: Result<Quote, QuoteError>) {
        result.withLock { $0 = newResult }
    }

    func whileAnswering(_ action: @escaping @MainActor @Sendable () -> Void) {
        hook.withLock { $0 = action }
    }

    func quote(for _: Ticker) async throws(QuoteError) -> Quote {
        count.withLock { $0 += 1 }
        if let action = hook.withLock({ $0 }) {
            await action()
        }
        return try result.withLock { $0 }.get()
    }
}

/// Answers each ticker's quote from `results`, keyed by symbol, and records
/// the tickers it was asked for. A ticker with no result is unavailable. A
/// request cancelled while it waits fails, as a network request would.
final class FakeTickerQuotes: QuoteProviding {
    private let results: Mutex<[String: Result<Quote, QuoteError>]>
    private let asked = Mutex<[String]>([])
    private let hook = Mutex<(@MainActor @Sendable () -> Void)?>(nil)

    init(_ results: [String: Result<Quote, QuoteError>]) {
        self.results = Mutex(results)
    }

    /// The symbols asked for, in the order asked.
    var requests: [String] {
        asked.withLock { $0 }
    }

    func answer(_ symbol: String, with result: Result<Quote, QuoteError>) {
        results.withLock { $0[symbol] = result }
    }

    /// Runs `action` on the main actor during the next request only, as a
    /// change made while it waits.
    func whileAnsweringNext(_ action: @escaping @MainActor @Sendable () -> Void) {
        hook.withLock { $0 = action }
    }

    func quote(for ticker: Ticker) async throws(QuoteError) -> Quote {
        asked.withLock { $0.append(ticker.symbol) }
        if let action = hook.withLock({ hook in defer { hook = nil }; return hook }) {
            await action()
        }
        if Task.isCancelled {
            throw .unavailable("Cancelled")
        }
        let result = results.withLock { $0[ticker.symbol] } ?? .failure(.unavailable("No fake result"))
        return try result.get()
    }
}

/// Holds every quote open until `release()`, then answers each at 10, and
/// counts how many quotes started and the most that ran at once.
final class GatedQuotes: QuoteProviding {
    private struct State {
        var started = 0
        var running = 0
        var peak = 0
        var isReleased = false
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    var startedCount: Int {
        state.withLock { $0.started }
    }

    var peakRunning: Int {
        state.withLock { $0.peak }
    }

    /// Lets the held quotes and every later one answer.
    func release() {
        let waiting = state.withLock { state in
            state.isReleased = true
            defer { state.waiting = [] }
            return state.waiting
        }
        waiting.forEach { $0.resume() }
    }

    func quote(for ticker: Ticker) async throws(QuoteError) -> Quote {
        state.withLock { state in
            state.started += 1
            state.running += 1
            state.peak = max(state.peak, state.running)
        }
        await withCheckedContinuation { continuation in
            let isReleased = state.withLock { state in
                if !state.isReleased {
                    state.waiting.append(continuation)
                }
                return state.isReleased
            }
            if isReleased {
                continuation.resume()
            }
        }
        state.withLock { $0.running -= 1 }
        return Quote(
            ticker: ticker,
            price: 10,
            asOf: Date(timeIntervalSince1970: 1_793_000_000),
            source: .close(sessionDate: "2026-10-23"),
        )
    }
}

/// A quote for `ticker` at `price`, as of `asOf`.
func makeQuote(
    ticker: String,
    price: Decimal,
    asOf: Date = Date(timeIntervalSince1970: 1_793_000_000),
) throws -> Quote {
    try Quote(ticker: Ticker(ticker), price: price, asOf: asOf, source: .liveQuote(delayed: true))
}

/// Answers each ticker's daily bars from `bars`, or every request with
/// `failure`, and records the requests it was sent. `whileAnswering` runs
/// on the main actor during each request, as a change made mid-check.
final class FakeDailyPrices: DailyPriceProviding {
    struct Request: Equatable {
        let ticker: String
        let startDate: String
        let endDate: String
        var interval = BarInterval.daily
    }

    private let bars: [String: [DailyBar]]
    private let failure: QuoteError?
    private let sent = Mutex<[Request]>([])
    private let hook = Mutex<(@MainActor @Sendable () -> Void)?>(nil)

    init(_ bars: [String: [DailyBar]] = [:], failure: QuoteError? = nil) {
        self.bars = bars
        self.failure = failure
    }

    var requests: [Request] {
        sent.withLock { $0 }
    }

    func whileAnswering(_ action: @escaping @MainActor @Sendable () -> Void) {
        hook.withLock { $0 = action }
    }

    func dailyBars(
        for ticker: Ticker,
        from startDate: String,
        through endDate: String,
        interval: BarInterval,
    ) async throws(QuoteError) -> [DailyBar] {
        sent.withLock {
            $0.append(Request(ticker: ticker.symbol, startDate: startDate, endDate: endDate, interval: interval))
        }
        if let action = hook.withLock({ $0 }) {
            await action()
        }
        if let failure {
            throw failure
        }
        return bars[ticker.symbol] ?? []
    }
}

/// Answers every section's request with its result, and counts them.
/// `whileAnswering` runs on the main actor during each request, as a change
/// made while it waits.
final class FakeResearchData: CompanyProfileProviding, ValuationMultiplesProviding {
    private let profile: Result<CompanyProfile, MarketDataError>
    private let multiples: Mutex<Result<ValuationMultiples, MarketDataError>>
    private let dividends: Mutex<Result<[Dividend], MarketDataError>>
    private let pressReleases: Mutex<Result<PressReleases, MarketDataError>>
    private let filings: Mutex<Result<[Filing], MarketDataError>>
    private let sent = Mutex(0)
    private let hook = Mutex<(@MainActor @Sendable () -> Void)?>(nil)

    init(
        profile: Result<CompanyProfile, MarketDataError> = .failure(.noData),
        multiples: Result<ValuationMultiples, MarketDataError> = .failure(.noData),
        dividends: Result<[Dividend], MarketDataError> = .failure(.noData),
        pressReleases: Result<PressReleases, MarketDataError> = .failure(.noData),
        filings: Result<[Filing], MarketDataError> = .failure(.noData),
    ) {
        self.profile = profile
        self.multiples = Mutex(multiples)
        self.dividends = Mutex(dividends)
        self.pressReleases = Mutex(pressReleases)
        self.filings = Mutex(filings)
    }

    var requestCount: Int {
        sent.withLock { $0 }
    }

    func answerMultiples(with result: Result<ValuationMultiples, MarketDataError>) {
        multiples.withLock { $0 = result }
    }

    func answerDividends(with result: Result<[Dividend], MarketDataError>) {
        dividends.withLock { $0 = result }
    }

    func answerPressReleases(with result: Result<PressReleases, MarketDataError>) {
        pressReleases.withLock { $0 = result }
    }

    func answerFilings(with result: Result<[Filing], MarketDataError>) {
        filings.withLock { $0 = result }
    }

    func whileAnswering(_ action: @escaping @MainActor @Sendable () -> Void) {
        hook.withLock { $0 = action }
    }

    func companyProfile(for _: Ticker) async throws(MarketDataError) -> CompanyProfile {
        await answering()
        return try profile.get()
    }

    func valuationMultiples(for _: Ticker) async throws(MarketDataError) -> ValuationMultiples {
        await answering()
        return try multiples.withLock { $0 }.get()
    }

    func dividends(for _: Ticker) async throws(MarketDataError) -> [Dividend] {
        await answering()
        return try dividends.withLock { $0 }.get()
    }

    func pressReleases(for _: Ticker) async throws(MarketDataError) -> PressReleases {
        await answering()
        return try pressReleases.withLock { $0 }.get()
    }

    func filings(for _: Ticker) async throws(MarketDataError) -> [Filing] {
        await answering()
        return try filings.withLock { $0 }.get()
    }

    private func answering() async {
        sent.withLock { $0 += 1 }
        if let action = hook.withLock({ $0 }) {
            await action()
        }
    }
}

extension FakeResearchData: DividendProviding, PressReleaseProviding, FilingProviding {}

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
