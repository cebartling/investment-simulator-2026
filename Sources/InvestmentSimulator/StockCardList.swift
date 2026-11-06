import InvestmentSimulatorPresentation
import SwiftUI

/// The Experiment section below its header (PIN-510): the action row, then
/// a card for each stock, by symbol.
struct StockCardList: View {
    let model: MainWindowModel

    var body: some View {
        // Redrawn every minute, so an order shows Expired once it expires,
        // a card whose orders all expired goes, and Check Orders enables
        // once a new day starts.
        TimelineView(.everyMinute) { context in
            content(at: context.date)
        }
    }

    private func content(at date: Date) -> some View {
        VStack(spacing: 12) {
            ExperimentActionRow(model: model, date: date)
            let cards = model.stockCards(at: date)
            if cards.isEmpty {
                ContentUnavailableView(
                    "No Purchases",
                    systemImage: "cart",
                    description: Text("Use Market Buy to purchase an investment with the cash balance."),
                )
                .frame(maxHeight: .infinity)
            } else {
                // A plain stack, not a lazy one: an experiment holds few
                // stocks, and each card keeps its table selection while it
                // scrolls out of view.
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(cards) { card in
                            StockCardView(model: model, card: card, date: date)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
