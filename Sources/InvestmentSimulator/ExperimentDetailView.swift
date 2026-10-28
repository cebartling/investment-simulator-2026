import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// The Experiment section's tables, below its header: the purchases, and
/// the buy and sell limit orders.
struct ExperimentDetailView: View {
    let purchases: [Purchase]
    let hasLimitOrders: Bool
    /// The limit orders as they stand at a date.
    let limitOrderRows: (Date) -> [LimitOrderRow]
    /// Whether the table includes expired and cancelled orders.
    @Binding var showsExpiredAndCancelledOrders: Bool
    let onSellLimit: (Purchase) -> Void
    let onCancelOrder: (UUID) -> Void
    /// Whether Check Orders can run at a date.
    let canCheckOrders: (Date) -> Bool
    let isCheckingOrders: Bool
    /// What the last Check Orders found, or why it failed.
    let orderCheckMessage: String?
    let onCheckOrders: () async -> Void

    @State private var selectedPurchase: Purchase.ID?
    @State private var selectedOrder: LimitOrderRow.ID?
    /// The order Cancel Order asks about, while it asks.
    @State private var orderToCancel: LimitOrderRow?

    var body: some View {
        VStack(spacing: 24) {
            if purchases.isEmpty, !hasLimitOrders {
                ContentUnavailableView(
                    "No Purchases",
                    systemImage: "cart",
                    description: Text("Use Buy to purchase an investment with the cash balance."),
                )
            } else {
                if !purchases.isEmpty {
                    purchasesTable
                }
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
        .confirmationDialog(
            cancelTitle,
            isPresented: Binding(get: { orderToCancel != nil }, set: {
                if !$0 {
                    orderToCancel = nil
                }
            }),
            presenting: orderToCancel,
        ) { row in
            Button("Cancel Order", role: .destructive) { onCancelOrder(row.id) }
            Button("Keep Order", role: .cancel) {}
        } message: { row in
            switch row.side {
            case .buy: Text("Its reserved cash will be free to spend again.")
            case .sell: Text("Its shares will be free to sell again.")
            }
        }
    }

    private var cancelTitle: String {
        guard let row = orderToCancel else {
            return ""
        }
        let side = row.side == .buy ? "buy" : "sell"
        return "Cancel the \(side) order for \(row.shares) \(row.ticker.symbol)?"
    }

    private var purchasesTable: some View {
        Table(purchases, selection: $selectedPurchase) {
            TableColumn("Date") { purchase in
                HStack {
                    Text(PriceDateFormatter().day(of: purchase.pricedAt, source: purchase.priceSource))
                    if case .limitOrderFill = purchase.priceSource {
                        Text("Limit fill")
                            .foregroundStyle(.secondary)
                    }
                }
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
                Toggle("Expired & Cancelled", isOn: $showsExpiredAndCancelledOrders)
                    .toggleStyle(.button)
                    .help("Show expired and cancelled orders")
                Button("Check Orders") {
                    Task { await onCheckOrders() }
                }
                .help("Fill orders whose limit a past session's prices reached")
                .disabled(!canCheckOrders(date))
                Button("Cancel Order…") {
                    orderToCancel = openRow(withID: selectedOrder, at: date)
                }
                .help("Cancel the selected open order")
                .disabled(openRow(withID: selectedOrder, at: date) == nil)
            }
            .padding(.horizontal)
            limitOrdersTable(at: date)
        }
    }

    private func limitOrdersTable(at date: Date) -> some View {
        Table(limitOrderRows(date), selection: $selectedOrder) {
            TableColumn("Side") { row in
                switch row.side {
                case .buy: Text("Buy")
                case .sell: Text("Sell")
                }
            }
            TableColumn("Ticker", value: \.ticker.symbol)
            TableColumn("Shares") { row in
                Text(row.shares, format: .number)
                    .monospaced()
            }
            .alignment(.numeric)
            TableColumn("Limit") { row in
                Text(row.limitPrice.amount, format: .currency(code: "USD"))
                    .monospaced()
            }
            .alignment(.numeric)
            TableColumn("Placed") { row in
                Text(row.placedAt.formatted(date: .abbreviated, time: .shortened))
            }
            TableColumn("Expires") { row in
                Text(row.expiresAt.formatted(date: .abbreviated, time: .shortened))
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
                case .cancelled:
                    Text("Cancelled")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu(forSelectionType: LimitOrderRow.ID.self) { ids in
            if let row = openRow(withID: ids.first, at: date) {
                Button("Cancel Order…") { orderToCancel = row }
            }
        }
    }

    /// The row of the order `id` if it is open at `date`.
    private func openRow(withID id: LimitOrderRow.ID?, at date: Date) -> LimitOrderRow? {
        limitOrderRows(date).first { $0.id == id && $0.status == .open }
    }

    private func purchase(withID id: Purchase.ID?) -> Purchase? {
        purchases.first { $0.id == id }
    }
}
