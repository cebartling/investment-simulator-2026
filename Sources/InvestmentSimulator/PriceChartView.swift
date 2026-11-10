import Charts
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// A ticker's price history: a range picker over a line of closes, with
/// its own loading, empty and error states. Research shows it bare; a stock
/// card's Chart pane marks the experiment's trades on it (PIN-515).
struct PriceChartView: View {
    let chart: PriceChartModel
    /// Placed in the same zone as `timeZone`, by `MainWindowModel.chartTrades(of:in:)`.
    var trades: [TradeMark.Plotted] = []
    let onShowRange: @MainActor (PriceRange) -> Void
    /// The one zone that places the points and lays out the axis.
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Range", selection: Binding(get: { chart.range }, set: { onShowRange($0) })) {
                ForEach(PriceRange.allCases, id: \.self) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            content
                .frame(height: 240)
        }
    }

    @ViewBuilder private var content: some View {
        switch chart.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(points):
            let plotted = ChartPoint.plot(points, in: timeZone)
            Chart {
                ForEach(plotted, id: \.date) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Close", point.close))
                    // A line through one point draws nothing.
                    if plotted.count == 1 {
                        PointMark(x: .value("Date", point.date), y: .value("Close", point.close))
                    }
                }
                ForEach(trades) { trade in
                    PointMark(x: .value("Date", trade.date), y: .value("Price", trade.price))
                        .foregroundStyle(by: .value("Trade", trade.side.label))
                        .symbol(by: .value("Trade", trade.side.label))
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            // Buys and sells differ by shape as well as color.
            .chartForegroundStyleScale([TradeMark.Side.buy.label: Color.green, TradeMark.Side.sell.label: .red])
            .chartSymbolScale([TradeMark.Side.buy.label: .triangle, TradeMark.Side.sell.label: .diamond])
            .chartLegend(trades.isEmpty ? .hidden : .automatic)
        case .empty:
            Text("No price history for \(chart.ticker.symbol).")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(error):
            VStack(spacing: 8) {
                Text(error.localizedDescription)
                    .foregroundStyle(.red)
                // A failed range isn't kept, so showing it again retries it.
                Button("Retry") { onShowRange(chart.range) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private extension PriceRange {
    var label: String {
        switch self {
        case .oneMonth: "1M"
        case .sixMonths: "6M"
        case .oneYear: "1Y"
        case .fiveYears: "5Y"
        }
    }
}

private extension TradeMark.Side {
    var label: String {
        switch self {
        case .buy: "Buy"
        case .sell: "Sell"
        }
    }
}
