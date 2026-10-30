import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Synchronization
import Testing

@MainActor
struct ResearchTabModelTests {
    @Test func `starts loading`() throws {
        let tab = try tab(FakeQuotes(.failure(.missingAPIKey)))

        #expect(tab.quoteState == .loading)
        #expect(!tab.needsAPIKey)
    }

    @Test func `refreshing shows the quote`() async throws {
        let quote = try makeQuote(ticker: "VTI", price: 316.9961)
        let tab = try tab(FakeQuotes(.success(quote)))

        await tab.refresh()

        #expect(tab.quoteState == .quoted(quote))
    }

    @Test(arguments: [
        QuoteError.missingAPIKey,
        .invalidAPIKey,
        .dailyLimitReached,
        .unavailable("Equibles is down"),
    ])
    func `refreshing keeps the error`(error: QuoteError) async throws {
        let tab = try tab(FakeQuotes(.failure(error)))

        await tab.refresh()

        #expect(tab.quoteState == .failed(error))
    }

    @Test(arguments: [
        (QuoteError.missingAPIKey, true),
        (.invalidAPIKey, true),
        (.dailyLimitReached, false),
        (.unavailable("Equibles is down"), false),
    ])
    func `only key errors need the API key`(error: QuoteError, needsKey: Bool) async throws {
        let tab = try tab(FakeQuotes(.failure(error)))

        await tab.refresh()

        #expect(tab.needsAPIKey == needsKey)
    }

    @Test func `a later refresh replaces a failure`() async throws {
        let quotes = FakeQuotes(.failure(.missingAPIKey))
        let tab = try tab(quotes)
        await tab.refresh()
        let quote = try makeQuote(ticker: "VTI", price: 12)
        quotes.answer(with: .success(quote))

        await tab.refresh()

        #expect(tab.quoteState == .quoted(quote))
        #expect(!tab.needsAPIKey)
    }

    @Test func `a refresh shows loading while it waits`() async throws {
        let quotes = FakeQuotes(.failure(.missingAPIKey))
        let tab = try tab(quotes)
        await tab.refresh()
        let seen = Seen()
        quotes.whileAnswering { seen.state = tab.quoteState }

        await tab.refresh()

        #expect(seen.state == .loading)
    }

    @Test func `a cancelled refresh leaves the state alone`() async throws {
        let quotes = try FakeTickerQuotes(["VTI": .success(makeQuote(ticker: "VTI", price: 12))])
        let tab = try tab(quotes)
        let run = Run()
        quotes.whileAnsweringNext { run.task?.cancel() }

        run.task = Task { await tab.refresh() }
        await run.task?.value

        #expect(tab.quoteState == .loading)
    }

    @Test func `the chart starts loading six months`() throws {
        let tab = try tab(FakeQuotes(.failure(.missingAPIKey)))

        #expect(tab.chartRange == .sixMonths)
        #expect(tab.chartState == .loading)
    }

    @Test func `loading quotes and charts six months of daily closes, oldest first`() async throws {
        let quote = try makeQuote(ticker: "VTI", price: 12)
        let prices = try FakeDailyPrices(["VTI": [bar("2026-10-28", close: 12), bar("2026-04-29", close: 10)]])
        let tab = try tab(FakeQuotes(.success(quote)), prices: prices)

        await tab.load()

        #expect(tab.quoteState == .quoted(quote))
        #expect(closes(tab) == [10, 12])
        #expect(prices.requests == [.init(ticker: "VTI", startDate: "2026-04-29", endDate: "2026-10-29")])
    }

    @Test func `no bars is an empty chart`() async throws {
        let tab = try tab(FakeQuotes(.failure(.missingAPIKey)))

        await tab.load()

        #expect(tab.chartState == .empty)
    }

    @Test func `a chart error stays in the chart`() async throws {
        let quote = try makeQuote(ticker: "VTI", price: 12)
        let tab = try tab(FakeQuotes(.success(quote)), prices: FakeDailyPrices(failure: .dailyLimitReached))

        await tab.load()

        #expect(tab.chartState == .failed(.dailyLimitReached))
        #expect(tab.quoteState == .quoted(quote))
    }

    @Test func `no history for a quoted ticker is an empty chart, not an error`() async throws {
        let quote = try makeQuote(ticker: "VTI", price: 12)
        let prices = try FakeDailyPrices(failure: .unknownTicker(Ticker("VTI")))
        let tab = try tab(FakeQuotes(.success(quote)), prices: prices)

        await tab.load()

        #expect(tab.chartState == .empty)
    }

    @Test func `a late failure doesn't hide a newer chart of the same range`() async throws {
        let prices = try AnswersFirstLate(first: .failure(.dailyLimitReached), later: [bar("2026-10-28", close: 12)])
        let tab = try ResearchTabModel(
            ticker: Ticker("VTI"),
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: prices,
            profiles: FakeResearchData(),
            multiples: FakeResearchData(),
            clock: { Self.now },
        )
        prices.beforeAnsweringFirst { await tab.showRange(.sixMonths) }

        await tab.showRange(.sixMonths)

        #expect(closes(tab) == [12])
    }

    @Test func `a late chart of another range doesn't replace the range shown`() async throws {
        let prices = try AnswersFirstLate(
            first: .success([bar("2026-10-28", close: 10)]),
            later: [bar("2026-10-28", close: 12)],
        )
        let tab = try ResearchTabModel(
            ticker: Ticker("VTI"),
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: prices,
            profiles: FakeResearchData(),
            multiples: FakeResearchData(),
            clock: { Self.now },
        )
        prices.beforeAnsweringFirst { await tab.showRange(.oneYear) }

        await tab.showRange(.sixMonths)

        #expect(tab.chartRange == .oneYear)
        #expect(closes(tab) == [12])
    }

    @Test func `showing a failed range again retries it`() async throws {
        let prices = FakeDailyPrices(failure: .unavailable("Couldn't reach Equibles."))
        let tab = try tab(FakeQuotes(.failure(.missingAPIKey)), prices: prices)
        await tab.load()

        await tab.showRange(.sixMonths)

        #expect(prices.requests.count == 2)
        #expect(tab.chartState == .failed(.unavailable("Couldn't reach Equibles.")))
    }

    @Test func `five years asks for weekly bars`() async throws {
        let prices = try FakeDailyPrices(["VTI": [bar("2026-10-28", close: 12)]])
        let tab = try tab(FakeQuotes(.failure(.missingAPIKey)), prices: prices)

        await tab.showRange(.fiveYears)

        #expect(tab.chartRange == .fiveYears)
        #expect(closes(tab) == [12])
        #expect(prices.requests == [
            .init(ticker: "VTI", startDate: "2021-10-29", endDate: "2026-10-29", interval: .weekly),
        ])
    }

    @Test func `going back to a loaded range asks for nothing`() async throws {
        let prices = try FakeDailyPrices(["VTI": [bar("2026-10-28", close: 12)]])
        let tab = try tab(FakeQuotes(.failure(.missingAPIKey)), prices: prices)
        await tab.load()
        await tab.showRange(.oneYear)

        await tab.showRange(.sixMonths)

        #expect(tab.chartRange == .sixMonths)
        #expect(closes(tab) == [12])
        #expect(prices.requests.map(\.startDate) == ["2026-04-29", "2025-10-29"])
    }

    @Test func `loading again fetches the chart again`() async throws {
        let prices = try FakeDailyPrices(["VTI": [bar("2026-10-28", close: 12)]])
        let tab = try tab(FakeQuotes(.failure(.missingAPIKey)), prices: prices)
        await tab.load()

        await tab.load()

        #expect(prices.requests.count == 2)
    }

    @Test func `a range cancelled before it starts changes nothing`() async throws {
        let prices = try FakeDailyPrices(["VTI": [bar("2026-10-28", close: 12)]])
        let tab = try tab(FakeQuotes(.failure(.missingAPIKey)), prices: prices)

        let task = Task { await tab.showRange(.oneYear) }
        task.cancel()
        await task.value

        #expect(tab.chartRange == .sixMonths)
        #expect(prices.requests.isEmpty)
    }

    @Test func `a cancelled range load leaves the chart alone`() async throws {
        let prices = try FakeDailyPrices(["VTI": [bar("2026-10-28", close: 12)]])
        let tab = try tab(FakeQuotes(.failure(.missingAPIKey)), prices: prices)
        let run = Run()
        prices.whileAnswering { run.task?.cancel() }

        run.task = Task { await tab.showRange(.oneYear) }
        await run.task?.value

        #expect(tab.chartState == .loading)
    }

    private func tab(
        _ quotes: some QuoteProviding,
        prices: FakeDailyPrices = FakeDailyPrices(),
    ) throws -> ResearchTabModel {
        try ResearchTabModel(
            ticker: Ticker("VTI"),
            quotes: quotes,
            dailyPrices: prices,
            profiles: FakeResearchData(),
            multiples: FakeResearchData(),
            clock: { Self.now },
        )
    }

    private func closes(_ tab: ResearchTabModel) -> [Decimal]? {
        guard case let .loaded(points) = tab.chartState else {
            return nil
        }
        return points.map(\.close)
    }

    /// 2 PM in New York on 2026-10-29.
    private static let now = ISO8601DateFormatter().date(from: "2026-10-29T18:00:00Z")!
}

/// A bar for `session` that opened, closed and ranged at `close`.
private func bar(_ session: String, close: Decimal) throws -> DailyBar {
    try DailyBar(sessionDate: session, open: close, high: close, low: close, close: close)
}

/// Answers its first request with `first`, but only once
/// `beforeAnsweringFirst` has run, as a newer request answering first.
/// Answers every later request with `later`.
private final class AnswersFirstLate: DailyPriceProviding {
    private let first: Result<[DailyBar], QuoteError>
    private let later: [DailyBar]
    private let count = Mutex(0)
    private let hook = Mutex<(@MainActor @Sendable () async -> Void)?>(nil)

    init(first: Result<[DailyBar], QuoteError>, later: [DailyBar]) {
        self.first = first
        self.later = later
    }

    func beforeAnsweringFirst(_ action: @escaping @MainActor @Sendable () async -> Void) {
        hook.withLock { $0 = action }
    }

    func dailyBars(
        for _: Ticker,
        from _: String,
        through _: String,
        interval _: BarInterval,
    ) async throws(QuoteError) -> [DailyBar] {
        let isFirst = count.withLock { count in
            count += 1
            return count == 1
        }
        guard isFirst else {
            return later
        }
        if let action = hook.withLock({ $0 }) {
            await action()
        }
        return try first.get()
    }
}

@MainActor
private final class Seen {
    var state: ResearchTabModel.QuoteState?
}

@MainActor
private final class Run {
    var task: Task<Void, Never>?
}
