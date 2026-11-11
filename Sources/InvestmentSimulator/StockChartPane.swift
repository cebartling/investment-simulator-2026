import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// An open stock card's Chart pane (PIN-515): the ticker's closes, with the
/// experiment's trades of it marked on them, each at its session and price.
struct StockChartPane: View {
    let model: MainWindowModel
    let ticker: Ticker
    /// The zone the trades are placed in, the one the chart's axis uses.
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        let chart = model.priceChart(of: ticker)
        PriceChartView(
            chart: chart,
            trades: model.chartTrades(of: ticker, in: timeZone),
            onShowRange: { model.showRange($0, of: ticker) },
        )
        // A range loaded that day and since the last Refresh Prices, or still
        // loading, isn't asked for again, so showing the pane again then asks
        // for nothing (PIN-519).
        .task(id: ticker) { await model.showChart(of: ticker).value }
    }
}
