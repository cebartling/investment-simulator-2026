import InvestmentSimulatorPresentation
import SwiftUI

/// The experiment's status bar (PIN-411): a failed save, and the state of
/// the holdings' prices with Refresh Prices, which also requotes the
/// tickers stock cards with no shares asked for (PIN-511).
struct ExperimentFooter: View {
    let model: MainWindowModel

    var body: some View {
        HStack(spacing: 12) {
            if let saveError = model.saveError {
                Text("Couldn't save: \(saveError)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(saveError)
                    .foregroundStyle(.red)
            }
            Spacer()
            // Secondary; the button keeps its own color,
            // so it reads as disabled when it is.
            pricesStatus
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Button("Refresh Prices", systemImage: "arrow.clockwise") {
                Task {
                    await model.holdingsPrices.refreshPrices(holding: model.experiment.heldTickers)
                }
            }
            .buttonStyle(.borderless)
            .help("Get the latest price of each stock")
            .disabled(!model.holdingsPrices.canRefresh(holding: model.experiment.heldTickers))
        }
        .font(.callout)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        // Prices every held ticker when the window opens, and each ticker
        // newly held after a buy or a fill. Changing holdings cancels a
        // pricing still running and starts one for the new set.
        .task(id: model.experiment.heldTickers) {
            await model.holdingsPrices.priceNewHoldings(of: model.experiment.heldTickers)
        }
    }

    /// When the prices are from, or why Total Value and Gain/Loss have none.
    @ViewBuilder private var pricesStatus: some View {
        switch model.holdingsPrices.valuation(of: model.experiment) {
        case let .valued(_, _, pricesAsOf?):
            Text("Prices as of \(pricesAsOf.formatted(date: .abbreviated, time: .shortened))")
        case .valued:
            EmptyView()
        case .pricing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Getting prices…")
            }
        case let .unpriced(error):
            Text(error.localizedDescription)
                .help(error.localizedDescription)
        }
    }
}
