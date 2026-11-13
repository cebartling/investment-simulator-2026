import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// A stock card's Chart pane (PIN-515).
extension MainWindowModelTests {
    @Test func `the Chart pane follows Overview`() {
        #expect(StockPane.allCases == [.overview, .chart, .purchases, .sales, .orders])
    }

    @Test func `each card keeps one chart, starting at six months`() async throws {
        let vti = try Ticker("VTI")
        let model = try await makeChartModel()

        let chart = model.priceChart(of: vti)

        #expect(model.priceChart(of: vti) === chart)
        #expect(try model.priceChart(of: Ticker("AAPL")) !== chart)
        #expect(chart.range == .sixMonths)
    }

    @Test func `showing a card's range charts it`() async throws {
        let vti = try Ticker("VTI")
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let model = try await makeChartModel(prices: prices)

        await model.showRange(.oneYear, of: vti).value

        #expect(model.priceChart(of: vti).range == .oneYear)
        #expect(model.priceChart(of: vti).state == .loaded([ChartPoint(sessionDate: "2026-10-26", close: 1)]))
        #expect(prices.requests.map(\.startDate) == ["2025-10-27"])
    }

    @Test func `a range shown before the last one loads replaces it`() async throws {
        let vti = try Ticker("VTI")
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let model = try await makeChartModel(prices: prices)

        let first = model.showRange(.oneYear, of: vti)
        let second = model.showRange(.fiveYears, of: vti)
        await first.value
        await second.value

        #expect(model.priceChart(of: vti).range == .fiveYears)
        #expect(prices.requests.map(\.interval) == [.weekly])
    }

    @Test func `showing a card's chart again while it loads asks once`() async throws {
        let vti = try Ticker("VTI")
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let model = try await makeChartModel(prices: prices)
        let again = Run()
        // The pane shows again, as after switching panes, while its range loads.
        prices.whileAnswering { again.task = again.task ?? model.showChart(of: vti) }

        await model.showChart(of: vti).value
        await again.task?.value

        #expect(prices.requests.count == 1)
        #expect(model.priceChart(of: vti).state == .loaded([ChartPoint(sessionDate: "2026-10-26", close: 1)]))
    }

    @Test func `showing a card's chart again after it fails asks again`() async throws {
        let vti = try Ticker("VTI")
        let prices = FakeDailyPrices(failure: .dailyLimitReached)
        let model = try await makeChartModel(prices: prices)
        await model.showChart(of: vti).value

        await model.showChart(of: vti).value

        #expect(prices.requests.count == 2)
        #expect(model.priceChart(of: vti).state == .failed(.dailyLimitReached))
    }

    @Test func `showing a card's chart again the same day asks for nothing`() async throws {
        let vti = try Ticker("VTI")
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let model = try await makeChartModel(prices: prices)
        await model.showChart(of: vti).value

        await model.showChart(of: vti).value

        #expect(prices.requests.count == 1)
    }

    @Test func `showing a card's chart on a new day loads it again`() async throws {
        let vti = try Ticker("VTI")
        var now = fixedNow
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let model = try await makeChartModel(prices: prices, clock: { now })
        await model.showChart(of: vti).value

        now = fixedNow.addingTimeInterval(86400)
        await model.showChart(of: vti).value

        #expect(prices.requests.count == 2)
        #expect(prices.requests.last?.endDate == PriceRange.sixMonths.sessions(endingAt: now).upperBound)
    }

    @Test func `a range picked on a new day loads again`() async throws {
        let vti = try Ticker("VTI")
        var now = fixedNow
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let model = try await makeChartModel(prices: prices, clock: { now })
        await model.showRange(.oneYear, of: vti).value
        await model.showRange(.sixMonths, of: vti).value

        now = fixedNow.addingTimeInterval(86400)
        await model.showRange(.oneYear, of: vti).value

        #expect(prices.requests.count == 3)
        #expect(prices.requests.last?.endDate == PriceRange.oneYear.sessions(endingAt: now).upperBound)
    }

    @Test func `a chart showing loads again on Refresh Prices`() async throws {
        let vti = try Ticker("VTI")
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let quotes = FakeQuotes(.failure(.missingAPIKey))
        let model = try await makeChartModel(
            purchases: [makeChartPurchase(source: .close(sessionDate: "2026-10-23"))],
            prices: prices,
            quotes: quotes,
        )
        model.toggleExpansion(of: vti)
        model.selectPane(.chart, for: vti)
        await model.showChart(of: vti).value

        await model.refreshPrices()

        #expect(prices.requests.count == 2)
        #expect(model.priceChart(of: vti).state == .loaded([ChartPoint(sessionDate: "2026-10-26", close: 1)]))
        // It still quotes the holdings, as Refresh Prices did before.
        #expect(quotes.requestCount == 1)
    }

    @Test func `a hidden chart loads again once shown after Refresh Prices`() async throws {
        let vti = try Ticker("VTI")
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let model = try await makeChartModel(prices: prices)
        model.toggleExpansion(of: vti)
        await model.showChart(of: vti).value

        // The card shows Overview, so its chart waits to be shown.
        await model.refreshPrices()
        #expect(prices.requests.count == 1)

        await model.showChart(of: vti).value
        #expect(prices.requests.count == 2)
    }

    @Test func `a closed card's chart loads again once shown after Refresh Prices`() async throws {
        let vti = try Ticker("VTI")
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let model = try await makeChartModel(prices: prices)
        model.toggleExpansion(of: vti)
        model.selectPane(.chart, for: vti)
        await model.showChart(of: vti).value
        model.toggleExpansion(of: vti)

        // Chart stays selected, but the card is closed, so nothing shows it.
        await model.refreshPrices()
        #expect(prices.requests.count == 1)

        await model.showChart(of: vti).value
        #expect(prices.requests.count == 2)
    }

    @Test func `picking 1M after the Overview loads asks for no bars`() async throws {
        let vti = try Ticker("VTI")
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let model = try await makeChartModel(prices: prices)
        await model.loadLatestSession(of: vti)

        await model.showRange(.oneMonth, of: vti).value

        #expect(prices.requests.count == 1)
        #expect(model.priceChart(of: vti).state == .loaded([ChartPoint(sessionDate: "2026-10-26", close: 1)]))
        #expect(model.priceChart(of: vti).shownSessions == PriceRange.oneMonth.sessions(endingAt: fixedNow))
    }

    @Test func `picking 1M on a new day after the Overview loads asks again`() async throws {
        let vti = try Ticker("VTI")
        var now = fixedNow
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let model = try await makeChartModel(prices: prices, clock: { now })
        await model.loadLatestSession(of: vti)

        now = fixedNow.addingTimeInterval(86400)
        await model.showRange(.oneMonth, of: vti).value

        #expect(prices.requests.count == 2)
        #expect(prices.requests.last?.endDate == PriceRange.oneMonth.sessions(endingAt: now).upperBound)
    }

    @Test func `picking 1M after Refresh Prices asks again`() async throws {
        let vti = try Ticker("VTI")
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let model = try await makeChartModel(prices: prices)
        await model.loadLatestSession(of: vti)

        await model.refreshPrices()
        await model.showRange(.oneMonth, of: vti).value

        #expect(prices.requests.count == 2)
    }

    @Test func `bars the Overview asked for yesterday aren't kept for the chart`() async throws {
        let vti = try Ticker("VTI")
        let clock = Clock()
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let model = try await makeChartModel(prices: prices, clock: { clock.now })
        // The New York day ends while the Overview's month loads.
        prices.whileAnswering { clock.now = fixedNow.addingTimeInterval(86400) }
        await model.loadLatestSession(of: vti)

        await model.showRange(.oneMonth, of: vti).value

        #expect(prices.requests.count == 2)
        #expect(prices.requests.last?.endDate == PriceRange.oneMonth.sessions(endingAt: clock.now).upperBound)
    }

    @Test func `an Overview that fails keeps nothing for the chart`() async throws {
        let vti = try Ticker("VTI")
        let prices = FakeDailyPrices(failure: .dailyLimitReached)
        let model = try await makeChartModel(prices: prices)
        await model.loadLatestSession(of: vti)

        await model.showRange(.oneMonth, of: vti).value

        #expect(prices.requests.count == 2)
        #expect(model.priceChart(of: vti).state == .failed(.dailyLimitReached))
    }

    @Test func `the chart places only the trades in its range`() async throws {
        let vti = try Ticker("VTI")
        // 8:30 PM on Aug 31 in New York, before the month back from fixedNow.
        let august = try makeChartPurchase(
            pricedAt: Date(timeIntervalSince1970: 1_788_222_600),
            source: .liveQuote(delayed: true),
        )
        let october = try makeChartPurchase(source: .close(sessionDate: "2026-10-23"))
        let model = try await makeChartModel(purchases: [august, october])

        await model.showRange(.oneMonth, of: vti).value
        let monthTrades = model.chartTrades(of: vti, in: .gmt)
        await model.showRange(.sixMonths, of: vti).value
        let halfYearTrades = model.chartTrades(of: vti, in: .gmt)

        #expect(monthTrades.map(\.id) == [october.id])
        #expect(halfYearTrades.map(\.id) == [august.id, october.id])
    }

    @Test func `a chart loaded on an earlier day still marks the trades in its bars`() async throws {
        let vti = try Ticker("VTI")
        var now = fixedNow
        // Monday, Sep 28: the first session of the month back from fixedNow (Oct 27).
        let firstSession = try makeChartPurchase(source: .close(sessionDate: "2026-09-28"))
        let threeDaysLater = fixedNow.addingTimeInterval(3 * 86400)
        // Made after the bars loaded, so it shows past the last close (ADR-0027).
        let madeToday = try makeChartPurchase(pricedAt: threeDaysLater, source: .liveQuote(delayed: true))
        let prices = try FakeDailyPrices([
            "VTI": [makeDailyBar(session: "2026-09-28", high: 1), makeDailyBar(session: "2026-10-26", high: 1)],
        ])
        let model = try await makeChartModel(purchases: [firstSession, madeToday], prices: prices, clock: { now })
        await model.showRange(.oneMonth, of: vti).value

        // The pane stays open, so nothing asks for the month's bars again (PIN-520).
        now = threeDaysLater
        let trades = model.chartTrades(of: vti, in: .gmt)

        #expect(prices.requests.count == 1)
        #expect(model.priceChart(of: vti).state == .loaded([
            ChartPoint(sessionDate: "2026-09-28", close: 1),
            ChartPoint(sessionDate: "2026-10-26", close: 1),
        ]))
        #expect(trades.map(\.id) == [firstSession.id, madeToday.id])
    }

    @Test func `a clock set back before the bars still marks the trades in them`() async throws {
        let vti = try Ticker("VTI")
        var now = fixedNow
        let purchase = try makeChartPurchase(source: .close(sessionDate: "2026-09-28"))
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-09-28", high: 1)]])
        let model = try await makeChartModel(purchases: [purchase], prices: prices, clock: { now })
        await model.showRange(.oneMonth, of: vti).value

        // Aug 28, before the bars' first session, as when the Mac's date is
        // set back.
        now = fixedNow.addingTimeInterval(-60 * 86400)

        #expect(model.chartTrades(of: vti, in: .gmt).map(\.id) == [purchase.id])
    }

    @Test func `a chart keeps its trades marked on the bars it draws until they reload`() async throws {
        let vti = try Ticker("VTI")
        let purchase = try makeChartPurchase(source: .close(sessionDate: "2026-10-23"))
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let model = try await makeChartModel(purchases: [purchase], prices: prices)
        await model.showChart(of: vti).value

        // Nothing shows the chart, so Refresh Prices only has it ask again
        // once shown, and until then it still draws the bars it loaded.
        await model.refreshPrices()

        #expect(model.priceChart(of: vti).state == .loaded([ChartPoint(sessionDate: "2026-10-26", close: 1)]))
        #expect(model.chartTrades(of: vti, in: .gmt).map(\.id) == [purchase.id])
    }

    @Test func `drawing a card's Chart pane changes nothing another card's pane observes`() async throws {
        let vti = try Ticker("VTI")
        let aapl = try Ticker("AAPL")
        let model = try await makeChartModel()
        // What `StockChartPane.body` reads.
        let draw = { (ticker: Ticker) in
            _ = model.priceChart(of: ticker)
            _ = model.chartTrades(of: ticker, in: .gmt)
        }
        draw(vti)

        let changed = changesObserved(by: { draw(vti) }, when: { draw(aapl) })

        #expect(!changed)
    }

    private func makeChartPurchase(
        pricedAt: Date = Date(timeIntervalSince1970: 0),
        source: PriceSource,
    ) throws -> Purchase {
        try Purchase(
            id: UUID(),
            ticker: Ticker("VTI"),
            shares: 1,
            pricePerShare: 10,
            pricedAt: pricedAt,
            priceSource: source,
        )
    }

    private func makeChartModel(
        purchases: [Purchase] = [],
        prices: FakeDailyPrices = FakeDailyPrices(),
        quotes: FakeQuotes = FakeQuotes(.failure(.missingAPIKey)),
        clock: @escaping () -> Date = { fixedNow },
    ) async throws -> MainWindowModel {
        try await loadedModel(
            experiment: Experiment(cashBalance: Money(10000), purchases: purchases),
            quotes: quotes,
            dailyPrices: prices,
            clock: clock,
        )
    }
}

@MainActor
private final class Run {
    var task: Task<Void, Never>?
}

/// A clock a fake can move on while it answers.
@MainActor
private final class Clock {
    var now = fixedNow
}
