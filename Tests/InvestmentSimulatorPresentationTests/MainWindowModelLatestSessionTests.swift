import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// A stock card's Overview: its ticker's latest settled session (PIN-510).
extension MainWindowModelTests {
    @Test func `the Overview shows the latest session of the past month`() async throws {
        let latest = try DailyBar(sessionDate: "2026-10-29", open: 11, high: 13, low: 10, close: 12)
        let prices = try FakeDailyPrices(["VTI": [
            makeDailyBar(session: "2026-10-27", high: 20),
            latest,
            makeDailyBar(session: "2026-10-28", high: 30),
        ]])
        let model = try await makeSessionModel(prices: prices)

        try await model.loadLatestSession(of: Ticker("VTI"))

        let sessions = PriceRange.oneMonth.sessions(endingAt: fixedNow)
        #expect(try model.latestSessions[Ticker("VTI")] == .loaded(latest))
        #expect(prices.requests == [FakeDailyPrices.Request(
            ticker: "VTI",
            startDate: sessions.lowerBound,
            endDate: sessions.upperBound,
        )])
    }

    @Test func `a latest session loads once`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-29", high: 13)]])
        let model = try await makeSessionModel(prices: prices)

        try await model.loadLatestSession(of: Ticker("VTI"))
        try await model.loadLatestSession(of: Ticker("VTI"))

        #expect(prices.requests.count == 1)
    }

    @Test func `a latest session loads again once a new day starts`() async throws {
        var now = fixedNow
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-29", high: 13)]])
        let model = try await makeSessionModel(prices: prices, clock: { now })
        try await model.loadLatestSession(of: Ticker("VTI"))

        now = fixedNow.addingTimeInterval(86400)
        try await model.loadLatestSession(of: Ticker("VTI"))

        #expect(prices.requests.count == 2)
        #expect(prices.requests.last?.endDate == PriceRange.oneMonth.sessions(endingAt: now).upperBound)
    }

    @Test func `a ticker with no sessions in the past month has none to show`() async throws {
        let model = try await makeSessionModel(prices: FakeDailyPrices())

        try await model.loadLatestSession(of: Ticker("VTI"))

        #expect(try model.latestSessions[Ticker("VTI")] == .empty)
    }

    @Test func `an unknown ticker has no session to show`() async throws {
        let prices = try FakeDailyPrices(failure: .unknownTicker(Ticker("VTI")))
        let model = try await makeSessionModel(prices: prices)

        try await model.loadLatestSession(of: Ticker("VTI"))

        #expect(try model.latestSessions[Ticker("VTI")] == .empty)
    }

    @Test func `a session that failed to load says why and is asked for again the next time`() async throws {
        let prices = FakeDailyPrices(failure: .dailyLimitReached)
        let model = try await makeSessionModel(prices: prices)

        try await model.loadLatestSession(of: Ticker("VTI"))
        #expect(try model.latestSessions[Ticker("VTI")] == .failed(QuoteError.dailyLimitReached.localizedDescription))

        try await model.loadLatestSession(of: Ticker("VTI"))
        #expect(prices.requests.count == 2)
    }

    private func makeSessionModel(
        prices: FakeDailyPrices,
        clock: @escaping () -> Date = { fixedNow },
    ) async throws -> MainWindowModel {
        try await loadedModel(
            experiment: Experiment(cashBalance: Money(100)),
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: prices,
            clock: clock,
        )
    }
}
