import InvestmentSimulatorPresentation
import SwiftUI

/// Text-only buttons under the header tiles (PIN-483): buying a new
/// ticker, and checking every order (PIN-510). Selling, and buying more of a
/// ticker, are on its stock card.
struct ExperimentActionRow: View {
    @Bindable var model: MainWindowModel
    /// When the row is drawn, so Check Orders enables once a new day starts.
    let date: Date

    var body: some View {
        HStack(spacing: 8) {
            Button("Market Buy", action: model.beginPurchase)
                .help("Buy shares of a ticker now at the market price")
            Button("Buy Limit", action: model.beginBuyLimitOrder)
                .help("Place an order to buy shares once the price drops to a limit")
            Spacer()
            if hasOrders {
                orderControls
            }
        }
        .padding(.horizontal, 20)
    }

    private var hasOrders: Bool {
        !model.experiment.limitOrders.isEmpty || !model.experiment.buyLimitOrders.isEmpty
    }

    @ViewBuilder private var orderControls: some View {
        if model.isCheckingOrders {
            ProgressView()
                .controlSize(.small)
        }
        if let message = model.orderCheckMessage {
            Text(message)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(message)
        }
        // Here, not on a card: a card whose only orders expired or were
        // cancelled shows only while this is on.
        Toggle("Expired & Cancelled", isOn: $model.showsExpiredAndCancelledOrders)
            .toggleStyle(.button)
            .help("Show expired and cancelled orders")
        Button("Check Orders") {
            Task { await model.checkLimitOrders() }
        }
        .help("Fill orders whose limit a past session's prices reached")
        .disabled(!model.canCheckOrders(at: date))
    }
}
