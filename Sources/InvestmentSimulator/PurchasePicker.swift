import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// Chooses the purchase a sell sheet sells from (PIN-510). Each choice
/// shows its day, shares and price, so it replaces the sheet's purchase
/// price row.
struct PurchasePicker: View {
    let choices: [SellablePurchase]
    @Binding var selection: UUID

    var body: some View {
        Picker("Purchase", selection: $selection) {
            ForEach(choices) { choice in
                Text(label(for: choice.purchase))
                    .monospacedDigit()
                    .tag(choice.id)
            }
        }
    }

    /// Such as "Oct 23, 2026: 10 at $316.9961".
    private func label(for purchase: Purchase) -> String {
        let day = PriceDateFormatter().day(of: purchase.pricedAt, source: purchase.priceSource)
        let price = purchase.pricePerShare.formatted(.currency(code: "USD").precision(.fractionLength(2 ... 4)))
        return "\(day): \(purchase.shares) at \(price)"
    }
}
