import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// Pricing the held shares for the Experiment header (PIN-408).
@MainActor
struct HoldingsPricesModelTests {
    @Test func `an experiment with no holdings is valued without quotes`() async throws {
        let quotes = FakeTickerQuotes([:])
        let model = HoldingsPricesModel(quotes: quotes)
        let experiment = try Experiment(cashBalance: Money(500))

        await model.priceNewHoldings(of: experiment.heldTickers)

        #expect(quotes.requests.isEmpty)
        let expectedGain = try #require(experiment.gain(prices: [:]))
        #expect(model.valuation(of: experiment) == .valued(
            totalValue: Money(500),
            gain: expectedGain,
            pricesAsOf: nil,
        ))
    }

    @Test func `held tickers are pricing until quoted`() throws {
        let model = HoldingsPricesModel(quotes: FakeTickerQuotes([:]))

        #expect(try model.valuation(of: experiment()) == .pricing)
    }

    @Test func `each held ticker is quoted once`() async throws {
        let quotes = try FakeTickerQuotes(["VTI": .success(makeQuote(ticker: "VTI", price: 12))])
        let model = HoldingsPricesModel(quotes: quotes)

        try await model.priceNewHoldings(of: experiment(tickers: ["VTI", "VTI"]).heldTickers)

        #expect(quotes.requests == ["VTI"])
    }

    @Test func `priced holdings value the experiment as of the earliest quote`() async throws {
        let earlier = Date(timeIntervalSince1970: 1_792_990_000)
        let quotes = try FakeTickerQuotes([
            "VTI": .success(makeQuote(ticker: "VTI", price: 12)),
            "AAPL": .success(makeQuote(ticker: "AAPL", price: 20, asOf: earlier)),
        ])
        let model = HoldingsPricesModel(quotes: quotes)
        let experiment = try experiment(tickers: ["VTI", "AAPL"])

        await model.priceNewHoldings(of: experiment.heldTickers)

        // 1000 − 2 × 10 cash, plus 12 + 20.
        let prices = try [Ticker("VTI"): Decimal(12), Ticker("AAPL"): Decimal(20)]
        let expectedGain = try #require(experiment.gain(prices: prices))
        #expect(model.valuation(of: experiment) == .valued(
            totalValue: Money(1012),
            gain: expectedGain,
            pricesAsOf: earlier,
        ))
    }

    @Test func `one failed ticker leaves the experiment unpriced with its error`() async throws {
        let quotes = try FakeTickerQuotes([
            "VTI": .success(makeQuote(ticker: "VTI", price: 12)),
            "AAPL": .failure(.dailyLimitReached),
        ])
        let model = HoldingsPricesModel(quotes: quotes)
        let experiment = try experiment(tickers: ["VTI", "AAPL"])

        await model.priceNewHoldings(of: experiment.heldTickers)

        #expect(model.valuation(of: experiment) == .unpriced(.dailyLimitReached))
    }

    @Test func `a missing API key leaves the experiment unpriced`() async throws {
        let model = HoldingsPricesModel(quotes: FakeTickerQuotes(["VTI": .failure(.missingAPIKey)]))
        let experiment = try experiment()

        await model.priceNewHoldings(of: experiment.heldTickers)

        #expect(model.valuation(of: experiment) == .unpriced(.missingAPIKey))
    }

    @Test func `refreshing quotes every held ticker again`() async throws {
        let quotes = try FakeTickerQuotes(["VTI": .success(makeQuote(ticker: "VTI", price: 12))])
        let model = HoldingsPricesModel(quotes: quotes)
        let experiment = try experiment()
        await model.priceNewHoldings(of: experiment.heldTickers)
        try quotes.answer("VTI", with: .success(makeQuote(ticker: "VTI", price: 15)))

        await model.refreshPrices(of: experiment.heldTickers)

        #expect(quotes.requests == ["VTI", "VTI"])
        let expectedGain = try #require(experiment.gain(prices: [Ticker("VTI"): 15]))
        #expect(model.valuation(of: experiment) == .valued(
            totalValue: Money(1005),
            gain: expectedGain,
            pricesAsOf: Date(timeIntervalSince1970: 1_793_000_000),
        ))
    }

    @Test func `a failed refresh keeps the ticker's last good price`() async throws {
        let quotes = try FakeTickerQuotes(["VTI": .success(makeQuote(ticker: "VTI", price: 12))])
        let model = HoldingsPricesModel(quotes: quotes)
        let experiment = try experiment()
        await model.priceNewHoldings(of: experiment.heldTickers)
        quotes.answer("VTI", with: .failure(.unavailable("offline")))

        await model.refreshPrices(of: experiment.heldTickers)

        let expectedGain = try #require(experiment.gain(prices: [Ticker("VTI"): 12]))
        #expect(model.valuation(of: experiment) == .valued(
            totalValue: Money(1002),
            gain: expectedGain,
            pricesAsOf: Date(timeIntervalSince1970: 1_793_000_000),
        ))
    }

    @Test func `new holdings quote only the tickers not yet quoted`() async throws {
        let quotes = try FakeTickerQuotes([
            "VTI": .success(makeQuote(ticker: "VTI", price: 12)),
            "AAPL": .failure(.missingAPIKey),
            "MSFT": .success(makeQuote(ticker: "MSFT", price: 30)),
        ])
        let model = HoldingsPricesModel(quotes: quotes)
        try await model.priceNewHoldings(of: experiment(tickers: ["VTI", "AAPL"]).heldTickers)

        try await model.priceNewHoldings(of: experiment(tickers: ["VTI", "AAPL", "MSFT"]).heldTickers)

        #expect(quotes.requests.sorted() == ["AAPL", "MSFT", "VTI"])
    }

    /// The window cancels a pricing run when holdings change and starts the
    /// next at once, while the cancelled run's quotes are still out.
    @Test func `a run cancelled mid-quote leaves its tickers to the next run`() async throws {
        let quotes = try FakeTickerQuotes([
            "VTI": .success(makeQuote(ticker: "VTI", price: 12)),
            "AAPL": .success(makeQuote(ticker: "AAPL", price: 20)),
        ])
        let model = HoldingsPricesModel(quotes: quotes)
        let grown = try experiment(tickers: ["VTI", "AAPL"])
        let runs = Runs()
        quotes.whileAnsweringNext {
            runs.first?.cancel()
            runs.second = Task { await model.priceNewHoldings(of: grown.heldTickers) }
        }

        let held = try experiment(tickers: ["VTI"]).heldTickers
        runs.first = Task { await model.priceNewHoldings(of: held) }
        await runs.first?.value
        await runs.second?.value

        #expect(model.valuation(of: grown) != .pricing)
        #expect(quotes.requests.sorted() == ["AAPL", "VTI", "VTI"])
    }

    @Test func `at most four quotes run at once`() async throws {
        let quotes = GatedQuotes()
        let model = HoldingsPricesModel(quotes: quotes)
        let experiment = try experiment(tickers: ["A", "B", "C", "D", "E", "F"])
        let run = Task { await model.priceNewHoldings(of: experiment.heldTickers) }
        while quotes.startedCount < 4 {
            await Task.yield()
        }
        // Gives a fifth quote every chance to start while four are held.
        for _ in 0 ..< 100 {
            await Task.yield()
        }

        #expect(quotes.startedCount == 4)
        quotes.release()
        await run.value
        #expect(quotes.startedCount == 6)
        #expect(quotes.peakRunning == 4)
        #expect(model.valuation(of: experiment) != .pricing)
    }

    @MainActor
    private final class Runs {
        var first: Task<Void, Never>?
        var second: Task<Void, Never>?
    }

    /// An experiment that started with 1000 and bought one share at 10 of
    /// each of `tickers`.
    private func experiment(tickers: [String] = ["VTI"]) throws -> Experiment {
        var experiment = try Experiment(cashBalance: Money(1000))
        for (index, ticker) in tickers.enumerated() {
            let purchase = try Purchase(
                id: #require(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))),
                ticker: Ticker(ticker),
                shares: 1,
                pricePerShare: 10,
                pricedAt: Date(timeIntervalSince1970: 1_793_000_000),
                priceSource: .liveQuote(delayed: true),
            )
            experiment = try experiment.purchasing(purchase, at: Date(timeIntervalSince1970: 1_793_000_000))
        }
        return experiment
    }
}
