import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// A stock card's Chart pane (PIN-515).
extension MainWindowModelTests {
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
    ) async throws -> MainWindowModel {
        try await loadedModel(
            experiment: Experiment(cashBalance: Money(10000), purchases: purchases),
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: prices,
            clock: { fixedNow },
        )
    }
}
