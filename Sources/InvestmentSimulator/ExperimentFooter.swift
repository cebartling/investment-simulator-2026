import InvestmentSimulatorPresentation
import SwiftUI

/// The window's status bar, under the sidebar and the detail (PIN-411):
/// the document's file, and the state of the holdings' prices with Refresh
/// Prices.
struct ExperimentFooter: View {
    let model: MainWindowModel
    let fileURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            Text(model.fileLabel(fileURL: fileURL))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(fileURL?.path(percentEncoded: false) ?? "")
            Spacer()
            pricesStatus
                .lineLimit(1)
            Button("Refresh Prices", systemImage: "arrow.clockwise") {
                Task {
                    await model.holdingsPrices.refreshPrices(of: model.experiment.heldTickers)
                }
            }
            .buttonStyle(.borderless)
            .help("Get the latest price of each holding")
            .disabled(model.holdingsPrices.isRefreshing || model.experiment.heldTickers.isEmpty)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
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
