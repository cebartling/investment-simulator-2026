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

    @Test func `bars kept for a range show without a request`() async throws {
        let prices = FakeDailyPrices()
        let chart = try makeChart(prices: prices)
        let month = PriceRange.oneMonth.sessions(endingAt: fixedNow)
        let bars = try [makeDailyBar(session: "2026-10-26", high: 1), makeDailyBar(session: "2026-10-23", high: 1)]

        chart.keep(bars, askedFor: month, as: .oneMonth)
        await chart.load(.oneMonth).value

        #expect(chart.state == .loaded([
            ChartPoint(sessionDate: "2026-10-23", close: 1),
            ChartPoint(sessionDate: "2026-10-26", close: 1),
        ]))
        #expect(chart.shownSessions == month)
        #expect(prices.requests.isEmpty)
    }

    @Test func `bars kept while that range fails to load still show`() async throws {
        let prices = FakeDailyPrices(failure: .dailyLimitReached)
        let chart = try makeChart(prices: prices)
        let month = PriceRange.oneMonth.sessions(endingAt: fixedNow)
        let bars = try [makeDailyBar(session: "2026-10-26", high: 1)]
        // The Overview's month arrives while the chart asks for its own (PIN-524).
        prices.whileAnswering { chart.keep(bars, askedFor: month, as: .oneMonth) }

        await chart.load(.oneMonth).value

        #expect(chart.state == .loaded([ChartPoint(sessionDate: "2026-10-26", close: 1)]))
        #expect(chart.shownSessions == month)
    }

    @Test func `a load asked for the day before doesn't replace the next day's bars kept meanwhile`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-23", high: 1)]])
        let chart = try makeChart(prices: prices)
        let nextMonth = PriceRange.oneMonth.sessions(endingAt: fixedNow.addingTimeInterval(86400))
        let bars = try [makeDailyBar(session: "2026-10-26", high: 1)]
        // The day ends while the chart asks for its month, and the Overview
        // hands over the new day's month before the answer comes (PIN-524).
        prices.whileAnswering { chart.keep(bars, askedFor: nextMonth, as: .oneMonth) }

        await chart.load(.oneMonth).value

        #expect(chart.state == .loaded([ChartPoint(sessionDate: "2026-10-26", close: 1)]))
        #expect(chart.shownSessions == nextMonth)
    }

    @Test func `forgetting the ranges not asked on a day keeps those that were`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let chart = try makeChart(prices: prices)
        await chart.load(.sixMonths).value
        let yesterdaysMonth = PriceRange.oneMonth.sessions(endingAt: fixedNow.addingTimeInterval(-86400))
        try chart.keep([makeDailyBar(session: "2026-10-23", high: 1)], askedFor: yesterdaysMonth, as: .oneMonth)

        chart.forgetRanges(notAskedOn: PriceRange.oneMonth.sessions(endingAt: fixedNow).upperBound)
        await chart.load(.sixMonths).value
        await chart.load(.oneMonth).value

        #expect(prices.requests.map(\.startDate) == [
            PriceRange.sixMonths.sessions(endingAt: fixedNow).lowerBound,
            PriceRange.oneMonth.sessions(endingAt: fixedNow).lowerBound,
        ])
    }

    @Test func `bars kept for another range leave what shows`() async throws {
        let prices = try FakeDailyPrices(["VTI": [makeDailyBar(session: "2026-10-26", high: 1)]])
        let chart = try makeChart(prices: prices)
        await chart.load(.sixMonths).value

        let bar = try DailyBar(sessionDate: "2026-10-23", open: 2, high: 2, low: 2, close: 2)
        chart.keep([bar], askedFor: PriceRange.oneMonth.sessions(endingAt: fixedNow), as: .oneMonth)

        #expect(chart.range == .sixMonths)
        #expect(chart.state == .loaded([ChartPoint(sessionDate: "2026-10-26", close: 1)]))
        #expect(chart.shownSessions == PriceRange.sixMonths.sessions(endingAt: fixedNow))
    }

    private func makeChart(prices: FakeDailyPrices) throws -> PriceChartModel {
        try PriceChartModel(ticker: Ticker("VTI"), dailyPrices: prices, clock: { fixedNow })
    }
}

private final class Run {
    var task: Task<Void, Never>?
}
