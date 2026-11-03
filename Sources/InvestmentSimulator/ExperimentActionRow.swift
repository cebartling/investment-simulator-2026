import SwiftUI

/// Text-only buttons for buying and selling, under the header tiles
/// (PIN-483). The sell buttons act on the selected purchase, so they are
/// off until `canSell`.
struct ExperimentActionRow: View {
    let canSell: Bool
    let onBuy: () -> Void
    let onBuyLimit: () -> Void
    let onSell: () -> Void
    let onSellLimit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("Market Buy", action: onBuy)
                .help("Buy shares of a ticker now at the market price")
            Button("Buy Limit", action: onBuyLimit)
                .help("Place an order to buy shares once the price drops to a limit")
            Button("Market Sell", action: onSell)
                .help("Sell shares of the selected purchase now at the market price")
                .disabled(!canSell)
            Button("Sell Limit", action: onSellLimit)
                .help("Place a sell limit order on the selected purchase")
                .disabled(!canSell)
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}
