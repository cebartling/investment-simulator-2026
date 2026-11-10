import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// An open stock card's panes (PIN-510): the ticker's Overview (PIN-511),
/// and its purchases, sales and orders, each with the buttons that add to
/// it.
struct StockCardPanes: View {
    let model: MainWindowModel
    let ticker: Ticker
    let heldShares: Int
    /// When the panes are drawn, so orders show as they stand then.
    let date: Date

    @State private var selectedPurchase: Purchase.ID?
    @State private var selectedOrder: LimitOrderRow.ID?
    /// The order Cancel Order asks about, while it asks.
    @State private var orderToCancel: LimitOrderRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Pane", selection: paneSelection) {
                ForEach(StockPane.allCases, id: \.self) { pane in
                    Text(pane.title)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            switch model.selectedPane(for: ticker) {
            case .overview:
                StockOverviewPane(model: model, ticker: ticker, heldShares: heldShares)
            case .chart:
                StockChartPane(model: model, ticker: ticker)
            case .purchases:
                purchasesPane
            case .sales:
                salesPane
            case .orders:
                ordersPane
            }
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
            Button("Cancel Order", role: .destructive) { model.cancelOrder(id: row.id) }
            Button("Keep Order", role: .cancel) {}
        } message: { row in
            switch row.side {
            case .buy: Text("Its reserved cash will be free to spend again.")
            case .sell: Text("Its shares will be free to sell again.")
            }
        }
    }

    private var paneSelection: Binding<StockPane> {
        Binding(get: { model.selectedPane(for: ticker) }, set: { model.selectPane($0, for: ticker) })
    }

    private var canSell: Bool {
        heldShares > 0
    }

    // MARK: Purchases

    private var purchasesPane: some View {
        let purchases = model.purchases(of: ticker)
        return VStack(alignment: .leading, spacing: 8) {
            Button("Market Buy") { model.beginPurchase(of: ticker) }
                .help("Buy more \(ticker.symbol) now at the market price")
            if purchases.isEmpty {
                emptyText("No purchases of \(ticker.symbol) yet.")
            } else {
                purchasesTable(purchases)
            }
        }
    }

    private func purchasesTable(_ purchases: [Purchase]) -> some View {
        Table(purchases, selection: $selectedPurchase) {
            TableColumn("Date") { purchase in
                HStack {
                    Text(PriceDateFormatter().tradeTime(of: purchase.pricedAt, source: purchase.priceSource))
                    if case .limitOrderFill = purchase.priceSource {
                        Text("Limit fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // Amounts are right-aligned and monospaced, so digits line up
            // down each column.
            TableColumn("Shares") { purchase in
                Text(purchase.shares, format: .number)
                    .monospaced()
            }
            .alignment(.numeric)
            TableColumn("Price") { purchase in
                Text(PriceFormatter().cents(purchase.pricePerShare))
                    .monospaced()
                    .help(ifPresent: PriceFormatter().full(purchase.pricePerShare))
            }
            .alignment(.numeric)
            TableColumn("Cost") { purchase in
                Text(purchase.cost.amount, format: .currency(code: "USD"))
                    .monospaced()
            }
            .alignment(.numeric)
        }
        .frame(height: Self.tableHeight(rows: purchases.count))
        .contextMenu(forSelectionType: Purchase.ID.self) { ids in
            if let purchase = purchases.first(where: { $0.id == ids.first }) {
                // A sold-out purchase has nothing left to sell.
                let isHeld = model.experiment.heldShares(of: purchase) > 0
                Button("Market Sell…") { model.beginSale(of: ticker, selecting: purchase.id) }
                    .disabled(!isHeld)
                Button("Sell Limit…") { model.beginLimitOrder(of: ticker, selecting: purchase.id) }
                    .disabled(!isHeld)
            }
        }
    }

    // MARK: Sales

    private var salesPane: some View {
        let rows = model.saleRows(of: ticker)
        return VStack(alignment: .leading, spacing: 8) {
            Button("Market Sell") { model.beginSale(of: ticker) }
                .help("Sell shares of one of this stock's purchases now at the market price")
                .disabled(!canSell)
            if rows.isEmpty {
                emptyText("No sales of \(ticker.symbol) yet.")
            } else {
                salesTable(rows)
            }
        }
    }

    private func salesTable(_ rows: [SaleRow]) -> some View {
        Table(rows) {
            TableColumn("Date") { row in
                switch row.kind {
                case let .market(source):
                    Text(PriceDateFormatter().tradeTime(ofSaleAt: row.soldAt, quotedAt: row.quotedAt, source: source))
                case let .limitFill(sessionDate):
                    HStack {
                        Text(PriceDateFormatter().day(ofSession: sessionDate))
                        Text("Limit fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            TableColumn("Shares") { row in
                Text(row.shares, format: .number)
                    .monospaced()
            }
            .alignment(.numeric)
            TableColumn("Price") { row in
                Text(PriceFormatter().cents(row.pricePerShare))
                    .monospaced()
                    .help(ifPresent: PriceFormatter().full(row.pricePerShare))
            }
            .alignment(.numeric)
            TableColumn("Proceeds") { row in
                Text(row.proceeds.amount, format: .currency(code: "USD"))
                    .monospaced()
            }
            .alignment(.numeric)
            TableColumn("Gain") { row in
                Text(row.realizedGain.amount, format: .currency(code: "USD"))
                    .monospaced()
                    // Colored as the header colors Gain/Loss.
                    .foregroundStyle(
                        row.realizedGain > .zero ? .green : row.realizedGain < .zero ? .red : .primary,
                    )
            }
            .alignment(.numeric)
        }
        .frame(height: Self.tableHeight(rows: rows.count))
    }

    // MARK: Orders

    private var ordersPane: some View {
        let rows = model.limitOrderRows(of: ticker, at: date)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Buy Limit") { model.beginBuyLimitOrder(of: ticker) }
                    .help("Place an order to buy more \(ticker.symbol) once the price drops to a limit")
                Button("Sell Limit") { model.beginLimitOrder(of: ticker) }
                    .help("Place a sell limit order on one of this stock's purchases")
                    .disabled(!canSell)
                Spacer()
                Button("Cancel Order…") {
                    orderToCancel = openRow(withID: selectedOrder, in: rows)
                }
                .help("Cancel the selected open order")
                .disabled(openRow(withID: selectedOrder, in: rows) == nil)
            }
            if rows.isEmpty {
                emptyText("No orders for \(ticker.symbol) to show.")
            } else {
                ordersTable(rows)
            }
        }
    }

    private func ordersTable(_ rows: [LimitOrderRow]) -> some View {
        Table(rows, selection: $selectedOrder) {
            TableColumn("Side") { row in
                switch row.side {
                case .buy: Text("Buy")
                case .sell: Text("Sell")
                }
            }
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
        .frame(height: Self.tableHeight(rows: rows.count))
        .contextMenu(forSelectionType: LimitOrderRow.ID.self) { ids in
            if let row = openRow(withID: ids.first, in: rows) {
                Button("Cancel Order…") { orderToCancel = row }
            }
        }
    }

    /// The row of the order `id` if it is open.
    private func openRow(withID id: LimitOrderRow.ID?, in rows: [LimitOrderRow]) -> LimitOrderRow? {
        rows.first { $0.id == id && $0.status == .open }
    }

    private var cancelTitle: String {
        guard let row = orderToCancel else {
            return ""
        }
        let side = row.side == .buy ? "buy" : "sell"
        return "Cancel the \(side) order for \(row.shares) \(row.ticker.symbol)?"
    }

    // MARK: Layout

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
    }

    /// Tall enough for the header and `rows` rows, up to six, past which the
    /// table scrolls. A table inside a scroll view has no height of its own.
    private static func tableHeight(rows: Int) -> CGFloat {
        let headerHeight: CGFloat = 28
        let rowHeight: CGFloat = 24
        // The inset style pads above the first row and below the last.
        let insets: CGFloat = 16
        return headerHeight + rowHeight * CGFloat(min(max(rows, 1), 6)) + insets
    }
}

private extension StockPane {
    var title: String {
        switch self {
        case .overview: "Overview"
        case .chart: "Chart"
        case .purchases: "Purchases"
        case .sales: "Sales"
        case .orders: "Orders"
        }
    }
}
