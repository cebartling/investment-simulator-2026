import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// The Experiment section's detail: the cash balance, shown large, the
/// purchases made with it, and the limit orders placed on them.
struct ExperimentDetailView: View {
    let cashBalance: Decimal
    let purchases: [Purchase]
    let hasLimitOrders: Bool
    /// The limit orders as they stand at a date.
    let limitOrderRows: (Date) -> [LimitOrderRow]
    let onSellLimit: (Purchase) -> Void
    /// Whether Check Orders can run at a date.
    let canCheckOrders: (Date) -> Bool
    let isCheckingOrders: Bool
    /// What the last Check Orders found, or why it failed.
    let orderCheckMessage: String?
    let onCheckOrders: () async -> Void

    @State private var selectedPurchase: Purchase.ID?

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
                purchasesTable
                if hasLimitOrders {
                    limitOrdersTable
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            Button("Sell Limit…", systemImage: "tag") {
                if let purchase = purchase(withID: selectedPurchase) {
                    onSellLimit(purchase)
                }
            }
            .help("Place a sell limit order on the selected purchase")
            // The selection can outlive its purchase, as after File › Revert To.
            .disabled(purchase(withID: selectedPurchase) == nil)
        }
    }

    private var purchasesTable: some View {
        Table(purchases, selection: $selectedPurchase) {
            TableColumn("Date") { purchase in
                Text(PriceDateFormatter().day(of: purchase.pricedAt, source: purchase.priceSource))
            }
            TableColumn("Ticker", value: \.ticker.symbol)
            // Amounts are right-aligned and monospaced, so digits line up
            // down each column.
            TableColumn("Shares") { purchase in
                Text(purchase.shares, format: .number)
                    .monospaced()
            }
            .alignment(.numeric)
            TableColumn("Price") { purchase in
                Text(purchase.pricePerShare, format: .currency(code: "USD").precision(.fractionLength(2 ... 4)))
                    .monospaced()
            }
            .alignment(.numeric)
            TableColumn("Cost") { purchase in
                Text(purchase.cost.amount, format: .currency(code: "USD"))
                    .monospaced()
            }
            .alignment(.numeric)
        }
        .contextMenu(forSelectionType: Purchase.ID.self) { ids in
            if let purchase = purchase(withID: ids.first) {
                Button("Sell Limit…") { onSellLimit(purchase) }
            }
        }
    }

    private var limitOrdersTable: some View {
        // Redrawn every minute, so an order shows Expired once it expires
        // and Check Orders enables once a new day starts.
        TimelineView(.everyMinute) { context in
            limitOrdersSection(at: context.date)
        }
    }

    private func limitOrdersSection(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Limit Orders")
                    .font(.headline)
                Spacer()
                if isCheckingOrders {
                    ProgressView()
                        .controlSize(.small)
                }
                if let orderCheckMessage {
                    Text(orderCheckMessage)
                        .foregroundStyle(.secondary)
                }
                Button("Check Orders") {
                    Task { await onCheckOrders() }
                }
                .help("Fill orders whose limit a past session's high reached")
                .disabled(!canCheckOrders(date))
            }
            .padding(.horizontal)
            limitOrdersTable(at: date)
        }
    }

    private func limitOrdersTable(at date: Date) -> some View {
        Table(limitOrderRows(date)) {
            TableColumn("Ticker", value: \.ticker.symbol)
            TableColumn("Shares") { row in
                Text(row.order.shares, format: .number)
                    .monospaced()
            }
            .alignment(.numeric)
            TableColumn("Limit") { row in
                Text(row.order.limitPrice.amount, format: .currency(code: "USD"))
                    .monospaced()
            }
            .alignment(.numeric)
            TableColumn("Placed") { row in
                Text(row.order.placedAt.formatted(date: .abbreviated, time: .shortened))
            }
            TableColumn("Expires") { row in
                Text(row.order.expiresAt.formatted(date: .abbreviated, time: .shortened))
            }
            TableColumn("Status") { row in
                switch row.status {
                case .open:
                    Text("Open")
                case let .filled(sessionDate):
                    Text("Filled \(PriceDateFormatter().day(ofSession: sessionDate))")
                case .expired:
                    Text("Expired")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func purchase(withID id: Purchase.ID?) -> Purchase? {
        purchases.first { $0.id == id }
    }
}
