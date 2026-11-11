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
