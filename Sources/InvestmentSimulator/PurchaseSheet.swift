import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// Buys shares of a ticker at a market price, paid from the experiment's cash.
struct PurchaseSheet: View {
    @Bindable var model: PurchaseModel
    let onBuy: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Buy Investment")
                .font(.title2.bold())
            Form {
                TextField("Ticker", text: $model.tickerText, prompt: Text("VTI"))
                if let message = model.tickerMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
                TextField("Shares", value: $model.shares, format: .number)
                if let message = model.sharesMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
                LabeledContent("Cash", value: model.availableCash.amount, format: .currency(code: "USD"))
                price
            }
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
        }
        .padding(20)
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
                    Text(sourceLabel(for: quote))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let cost = model.cost, let remaining = model.remainingCash {
                LabeledContent("Cost", value: cost.amount, format: .currency(code: "USD"))
                LabeledContent("Cash after", value: remaining.amount, format: .currency(code: "USD"))
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

    private func sourceLabel(for quote: Quote) -> String {
        switch quote.source {
        case .liveQuote(delayed: true):
            "15-minute delayed quote, \(quote.asOf.formatted(date: .abbreviated, time: .shortened))"
        case .liveQuote(delayed: false):
            "Live quote, \(quote.asOf.formatted(date: .abbreviated, time: .shortened))"
        case .close:
            "Close on \(quote.asOf.formatted(date: .abbreviated, time: .omitted))"
        }
    }
}
