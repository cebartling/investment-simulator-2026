import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// An open stock card's Overview (PIN-511): the ticker's quote, its change
/// since the previous close and, with shares held, their market value and
/// gain, above the latest settled session's prices (PIN-510).
struct StockOverviewPane: View {
    let model: MainWindowModel
    let ticker: Ticker
    let heldShares: Int

    var body: some View {
        StockOverviewContent(overview: model.overview(of: ticker))
            .task(id: ticker) { await model.loadLatestSession(of: ticker) }
            // A quote from a later session than the sessions were asked for
            // in needs them again for its change. Its own task, so a quote
            // arriving doesn't cancel the first load.
            .task(id: model.holdingsPrices.lastGoodQuote(of: ticker)?.sessionDate) {
                await model.reloadSessionsIfStale(of: ticker)
            }
            // Runs again when the last shares go while the Overview shows,
            // so Refresh Prices covers the ticker from then on.
            .task(id: OverviewQuoteRequest(ticker: ticker, isHeld: heldShares > 0)) {
                await model.priceOverview(of: ticker)
            }
    }
}

/// What the Overview's quote task runs for: it runs again when the ticker
/// stops or starts being held.
private struct OverviewQuoteRequest: Equatable {
    let ticker: Ticker
    let isHeld: Bool
}

/// Shows a `StockOverview`, which holds the rules.
private struct StockOverviewContent: View {
    let overview: StockOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            quote
            holding
            lastSession
        }
    }

    // MARK: - Quote

    /// The price and its change, labeled with where the quote came from, or
    /// why there's no price yet.
    private var quote: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch overview.price {
            case .loading:
                HStack(spacing: 8) {
                    priceText(nil)
                    ProgressView()
                        .controlSize(.small)
                }
            case let .quoted(quote):
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    priceText(quote.price)
                    if let change = overview.change {
                        Text(Self.changeText(change))
                            .monospacedDigit()
                            .foregroundStyle(Self.color(of: change.amount))
                    }
                }
                Text(PriceDateFormatter().label(for: quote))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case let .failed(error):
                priceText(nil)
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(error.localizedDescription)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func priceText(_ price: Decimal?) -> some View {
        Text(price.map(Self.perShare) ?? Self.unknown)
            .font(.title2)
            .monospacedDigit()
    }

    // MARK: - Holding

    /// The held shares' market value and gain, "—" for each until priced.
    @ViewBuilder private var holding: some View {
        switch overview.holding {
        case .notHeld:
            EmptyView()
        case .unpriced:
            HStack(spacing: 24) {
                figure("Market value", Self.unknown)
                figure("Unrealized gain", Self.unknown)
            }
        case let .priced(marketValue, gain):
            HStack(spacing: 24) {
                figure("Market value", marketValue.amount.formatted(.currency(code: "USD")))
                figure("Unrealized gain", Self.gainText(gain), color: Self.color(of: gain.amount.amount))
            }
        }
    }

    // MARK: - Last session

    /// The latest settled session's Open, High, Low and Close, labeled with
    /// its day, as PIN-510 shows them.
    @ViewBuilder private var lastSession: some View {
        switch overview.lastSession {
        case nil, .loading:
            HStack(spacing: 8) {
                sessionFigures(of: nil)
                ProgressView()
                    .controlSize(.small)
            }
        case let .loaded(recent):
            VStack(alignment: .leading, spacing: 6) {
                sessionFigures(of: recent.latest)
                Text("Last session, \(PriceDateFormatter().day(ofSession: recent.latest.sessionDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .empty:
            Text("No sessions in the past month.")
                .foregroundStyle(.secondary)
        case let .failed(message):
            Text(message)
                .foregroundStyle(.secondary)
                .help(message)
        }
    }

    /// Open, High, Low and Close, or "—" for each until the bar loads.
    private func sessionFigures(of bar: DailyBar?) -> some View {
        HStack(spacing: 24) {
            figure("Open", bar.map { Self.perShare($0.open) } ?? Self.unknown)
            figure("High", bar.map { Self.perShare($0.high) } ?? Self.unknown)
            figure("Low", bar.map { Self.perShare($0.low) } ?? Self.unknown)
            figure("Close", bar.map { Self.perShare($0.close) } ?? Self.unknown)
        }
    }

    // MARK: - Formatting

    private func figure(_ title: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(color)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    private static let unknown = "—"

    /// A price per share, with as many as 4 decimals, as quotes have.
    private static func perShare(_ price: Decimal) -> String {
        price.formatted(.currency(code: "USD").precision(.fractionLength(2 ... 4)))
    }

    /// Such as "+$5.94 (+1.73%)".
    private static func changeText(_ change: PriceChange) -> String {
        let amount = change.amount.formatted(
            .currency(code: "USD").precision(.fractionLength(2 ... 4)).sign(strategy: .always(showZero: false)),
        )
        return "\(amount) (\(percentText(change.percent)))"
    }

    /// Such as "+$123.40 (+3.65%)", or "(—)" for the percent of a cost of
    /// nothing.
    private static func gainText(_ gain: Gain) -> String {
        let amount = gain.amount.amount.formatted(.currency(code: "USD").sign(strategy: .always(showZero: false)))
        return "\(amount) (\(gain.percent.map(percentText) ?? unknown))"
    }

    private static func percentText(_ percent: Decimal) -> String {
        (percent / 100).formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)))
    }

    /// Green when up and red when down, as the header's Gain/Loss.
    private static func color(of amount: Decimal) -> Color {
        amount > 0 ? .green : amount < 0 ? .red : .primary
    }
}
