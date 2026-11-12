import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// A chart's own loading task (PIN-523), which Research and a stock card both
/// start through `load(_:)`.
@MainActor
struct PriceChartModelTests {
    @Test func `loading a range before the last one loads replaces it`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let chart = try makeChart(prices: prices)

        let first = chart.load(.oneYear)
        let second = chart.load(.fiveYears)
        await first.value
        await second.value

        #expect(chart.range == .fiveYears)
        #expect(chart.state == .loaded([ChartPoint(sessionDate: "2026-10-26", close: 1)]))
        #expect(prices.requests.map(\.interval) == [.weekly])
    }

    @Test func `the load in progress is the latest, and none once it loads`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let chart = try makeChart(prices: prices)
        let seen = Run()
        prices.whileAnswering { seen.task = chart.loadInProgress }

        let task = chart.load(.oneYear)
        await task.value

        #expect(seen.task == task)
        #expect(chart.loadInProgress == nil)
    }

    @Test func `cancelling the load leaves the chart loading`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let chart = try makeChart(prices: prices)
        prices.whileAnswering { chart.cancelLoad() }

        await chart.load(.oneYear).value

        #expect(chart.state == .loading)
        #expect(chart.loadInProgress == nil)
    }

    private func makeChart(prices: FakeDailyPrices) throws -> PriceChartModel {
        try PriceChartModel(ticker: Ticker("VTI"), dailyPrices: prices, clock: { fixedNow })
    }
}

private final class Run {
    var task: Task<Void, Never>?
}
