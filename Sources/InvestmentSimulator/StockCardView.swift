import InvestmentSimulatorPresentation
import SwiftUI

/// One stock in the experiment (PIN-510): its ticker, company name, shares
/// held and average price. Clicking it opens its panes below.
struct StockCardView: View {
    let model: MainWindowModel
    let card: StockCard
    /// When the card is drawn, so its orders show as they stand then.
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if isExpanded {
                Divider()
                StockCardPanes(model: model, ticker: card.ticker, heldShares: card.heldShares, date: date)
            }
        }
        .padding(12)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .task { await model.loadCompanyName(of: card.ticker) }
    }

    private var isExpanded: Bool {
        model.expandedTickers.contains(card.ticker)
    }

    private var header: some View {
        Button {
            model.toggleExpansion(of: card.ticker)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.ticker.symbol)
                        .font(.headline)
                    if let name = model.companyNames[card.ticker] {
                        Text(name)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 12)
                figure("Shares", card.heldShares.formatted())
                figure("Avg Price", averagePrice, help: card.averagePrice.flatMap { PriceFormatter().full($0) })
            }
            // The whole row clicks, not just its text.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .help(isExpanded ? "Hide this stock's panes" : "Show this stock's overview, purchases, sales and orders")
    }

    /// The price paid per share held, to the cent, or "—" with none held.
    private var averagePrice: String {
        card.averagePrice.map { PriceFormatter().cents($0) } ?? "—"
    }

    /// A title over its value, right-aligned, so values line up from card
    /// to card. The value is never truncated.
    private func figure(_ title: String, _ value: String, help: String? = nil) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .fixedSize()
                .help(ifPresent: help)
        }
        .frame(minWidth: 90, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }
}
