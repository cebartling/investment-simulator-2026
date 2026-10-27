import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// Buys shares of a ticker at a market price, paid from the experiment's cash.
struct PurchaseSheet: View {
    @Bindable var model: PurchaseModel
    let onBuy: () -> Void
    let onCancel: () -> Void

    var body: some View {
        // The grouped form insets its section by 20 points, so only the title
        // and buttons carry their own padding, to line up with its edges.
        VStack(alignment: .leading, spacing: 0) {
            Text("Buy Investment")
                .font(.title2.bold())
                .padding([.horizontal, .top], 20)
            Form {
                TextField("Ticker", text: $model.tickerText, prompt: Text("VTI"))
                    .onSubmit {
                        if model.canGetPrice {
                            Task { await model.getPrice() }
                        }
                    }
                if let message = model.tickerMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
                // The label sits outside the field so only the number is
                // monospaced.
                LabeledContent("Shares") {
                    TextField("Shares", value: $model.shares, format: .number)
                        .labelsHidden()
                        .monospaced()
                }
                if let message = model.sharesMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
                amountRow("Cash", model.availableCash.amount)
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
                Button("Buy", action: onBuy)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canBuy)
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
            if let cost = model.cost, let remaining = model.remainingCash {
                amountRow("Cost", cost.amount)
                amountRow("Cash after", remaining.amount)
            }
            if let message = model.shortfallMessage {
                Text(message)
                    .foregroundStyle(.red)
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
