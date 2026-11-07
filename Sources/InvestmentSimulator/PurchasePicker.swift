import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// Chooses the purchase a sell sheet sells from (PIN-510). Each choice
/// shows when it was priced (ADR-0024), its shares and price, so it
/// replaces the sheet's purchase price row.
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
        // A menu item can't have a tooltip, so the picker has the chosen
        // purchase's.
        .help(ifPresent: fullPrice)
    }

    /// The chosen purchase's price in full (PIN-513), or nil when it's whole
    /// cents.
    private var fullPrice: String? {
        choices.first { $0.id == selection }.flatMap { PriceFormatter().full($0.purchase.pricePerShare) }
    }

    /// Such as "Oct 23, 2026 at 10:31 AM: 10 at $317.00", or
    /// "Oct 23, 2026: 10 at $317.00" for a purchase at a close.
    private func label(for purchase: Purchase) -> String {
        let when = PriceDateFormatter().tradeTime(of: purchase.pricedAt, source: purchase.priceSource)
        let price = PriceFormatter().cents(purchase.pricePerShare)
        return "\(when): \(purchase.shares) at \(price)"
    }
}
