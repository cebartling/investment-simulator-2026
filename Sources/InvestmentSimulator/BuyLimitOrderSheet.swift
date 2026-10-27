import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// Places a buy limit order on a ticker at a typed limit price, which Get
/// Quote can prefill. The order reserves its cost from the available cash.
struct BuyLimitOrderSheet: View {
    @Bindable var model: BuyLimitOrderModel
    let onPlace: () -> Void
    let onCancel: () -> Void

    var body: some View {
        // The grouped form insets its section by 20 points, so only the title
        // and buttons carry their own padding, to line up with its edges.
        VStack(alignment: .leading, spacing: 0) {
            Text("Buy Limit")
                .font(.title2.bold())
                .padding([.horizontal, .top], 20)
            Form {
                TextField("Ticker", text: $model.tickerText, prompt: Text("VTI"))
                    .onSubmit {
                        if model.canGetQuote {
                            Task { await model.getQuote() }
                        }
                    }
                if let message = model.tickerMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
                LabeledContent("Limit price") {
                    HStack {
                        TextField("Limit price", value: $model.enteredPrice, format: .currency(code: "USD"))
                            .labelsHidden()
                            .monospaced()
                        Button("Get Quote") {
                            Task { await model.getQuote() }
                        }
                        .disabled(!model.canGetQuote)
                        if model.quoteState == .loading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                quote
                if let message = model.priceMessage {
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
                amountRow("Available cash", model.availableCash.amount)
                if let cost = model.cost {
                    amountRow("Cost", cost.amount)
                }
                if let message = model.shortfallMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
                LabeledContent("Expires") {
                    Text(model.expiresAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Place Order", action: onPlace)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canPlace)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 420)
        .interactiveDismissDisabled()
    }

    @ViewBuilder private var quote: some View {
        switch model.quoteState {
        case .none, .loading:
            EmptyView()
        case let .quoted(quote):
            Text(PriceDateFormatter().label(for: quote))
                .font(.caption)
                .foregroundStyle(.secondary)
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
