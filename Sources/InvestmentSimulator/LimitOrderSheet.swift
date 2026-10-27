import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// Places a sell limit order on one purchase, priced by a percent profit or
/// a typed limit price.
struct LimitOrderSheet: View {
    @Bindable var model: LimitOrderModel
    let onPlace: () -> Void
    let onCancel: () -> Void

    var body: some View {
        // The grouped form insets its section by 20 points, so only the title
        // and buttons carry their own padding, to line up with its edges.
        VStack(alignment: .leading, spacing: 0) {
            Text("Sell Limit: \(model.purchase.ticker.symbol)")
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
                Picker("Price by", selection: $model.mode) {
                    ForEach(LimitOrderModel.PriceMode.allCases, id: \.self) { mode in
                        Text(mode.title)
                    }
                }
                .pickerStyle(.segmented)
                priceInput
                if let message = model.priceMessage {
                    Text(message)
                        .foregroundStyle(.red)
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
                if let profit = model.profit {
                    amountRow("Profit", profit.amount)
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

    @ViewBuilder private var priceInput: some View {
        switch model.mode {
        case .profitPercent:
            LabeledContent("Target profit") {
                HStack {
                    TextField("Target profit", value: $model.profitPercent, format: .number)
                        .labelsHidden()
                        .monospaced()
                    Text("%")
                }
            }
            if let limitPrice = model.limitPrice {
                amountRow("Limit price", limitPrice.amount)
            }
        case .limitPrice:
            LabeledContent("Limit price") {
                TextField("Limit price", value: $model.enteredPrice, format: .currency(code: "USD"))
                    .labelsHidden()
                    .monospaced()
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

private extension LimitOrderModel.PriceMode {
    var title: String {
        switch self {
        case .profitPercent: "Percent profit"
        case .limitPrice: "Limit price"
        }
    }
}
