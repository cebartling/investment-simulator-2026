import InvestmentSimulatorCore
import SwiftUI

/// The Experiment section's detail: the cash balance, shown large, and the
/// purchases made with it.
struct ExperimentDetailView: View {
    let cashBalance: Decimal
    let purchases: [Purchase]

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Cash Balance")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(cashBalance, format: .currency(code: "USD"))
                    .font(.system(size: 56, weight: .semibold))
                    .monospacedDigit()
            }
            .padding(.top, 32)
            if purchases.isEmpty {
                ContentUnavailableView(
                    "No Purchases",
                    systemImage: "cart",
                    description: Text("Use Buy to purchase an investment with the cash balance."),
                )
            } else {
                Table(purchases) {
                    TableColumn("Date") { purchase in
                        Text(purchase.pricedAt, format: .dateTime.year().month().day())
                    }
                    TableColumn("Ticker", value: \.ticker.symbol)
                    TableColumn("Shares") { purchase in
                        Text(purchase.shares, format: .number)
                            .monospacedDigit()
                    }
                    TableColumn("Price") { purchase in
                        Text(purchase.pricePerShare, format: .currency(code: "USD").precision(.fractionLength(2 ... 4)))
                            .monospacedDigit()
                    }
                    TableColumn("Cost") { purchase in
                        Text(purchase.cost.amount, format: .currency(code: "USD"))
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
