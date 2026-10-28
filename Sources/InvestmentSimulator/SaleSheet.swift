import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// Sells free shares of one purchase at a market price, adding the proceeds
/// to the experiment's cash.
struct SaleSheet: View {
    @Bindable var model: SaleModel
    let onSell: () -> Void
    let onCancel: () -> Void

    var body: some View {
        // The grouped form insets its section by 20 points, so only the title
        // and buttons carry their own padding, to line up with its edges.
        VStack(alignment: .leading, spacing: 0) {
            Text("Market Sell: \(model.purchase.ticker.symbol)")
                .font(.title2.bold())
                .padding([.horizontal, .top], 20)
            Form {
                LabeledContent("Purchase price") {
                    Text(
                        model.purchase.pricePerShare,
                        format: .currency(code: "USD").precision(.fractionLength(2 ... 4)),
                    )
                    .monospaced()
                }
                LabeledContent("Shares") {
                    HStack {
                        TextField("Shares", value: $model.shares, format: .number)
                            .labelsHidden()
                            .monospaced()
                        Text("of \(model.availableShares) free")
                            .foregroundStyle(.secondary)
                    }
                }
                if let message = model.sharesMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
                amountRow("Cash", model.cashBalance.amount)
                price
            }
            .formStyle(.grouped)
            HStack {
                Button("Get Price") {
                    Task { await model.getPrice() }
                }
                .disabled(!model.canGetPrice)
                if model.priceState == .loading {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Sell", action: onSell)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSell)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 420)
        .interactiveDismissDisabled()
    }

    @ViewBuilder private var price: some View {
        switch model.priceState {
        case .none, .loading:
            EmptyView()
        case let .priced(quote):
            LabeledContent("Price") {
                VStack(alignment: .leading) {
                    Text(quote.price, format: .currency(code: "USD").precision(.fractionLength(2 ... 4)))
                        .monospaced()
                    Text(PriceDateFormatter().label(for: quote))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let proceeds = model.proceeds, let gain = model.realizedGain, let cashAfter = model.cashAfter {
                amountRow("Proceeds", proceeds.amount)
                amountRow("Realized gain", gain.amount)
                amountRow("Cash after", cashAfter.amount)
            }
        case let .failed(message):
            Text(message)
                .foregroundStyle(.red)
            if model.needsAPIKey {
                SettingsLink {
                    Text("Open Settings…")
                }
            }
        }
    }

    /// A dollar amount, monospaced so its digits line up with the rows
    /// around it.
    private func amountRow(_ title: LocalizedStringKey, _ amount: Decimal) -> some View {
        LabeledContent(title) {
            Text(amount, format: .currency(code: "USD"))
                .monospaced()
        }
    }
}
