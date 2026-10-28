import InvestmentSimulatorPresentation
import SwiftUI

struct ContentView: View {
    @Bindable var model: MainWindowModel
    /// Shown as the experiment's title when it has no name.
    let fileURL: URL?
    let onCreate: () -> Void
    let onPurchase: () -> Void
    let onSell: () -> Void
    let onPlaceLimitOrder: () -> Void
    let onPlaceBuyLimitOrder: () -> Void
    let onCancelOrder: (UUID) -> Void
    let onCheckOrders: () async -> Void
    let onSaveDetails: () -> Void

    var body: some View {
        NavigationSplitView {
            List(model.sections, selection: $model.selection) { section in
                Label(section.title, systemImage: section.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch model.selection {
            case .experiment:
                VStack(spacing: 16) {
                    ExperimentHeader(
                        model: model,
                        title: model.title(fileURL: fileURL),
                        onEditDetails: model.beginEditingDetails,
                    )
                    .padding(.top, 16)
                    ExperimentDetailView(
                        purchases: model.purchases,
                        hasLimitOrders: !model.experiment.limitOrders.isEmpty
                            || !model.experiment.buyLimitOrders.isEmpty,
                        saleRows: model.saleRows,
                        limitOrderRows: model.limitOrderRows(at:),
                        showsExpiredAndCancelledOrders: $model.showsExpiredAndCancelledOrders,
                        onSell: model.beginSale,
                        onSellLimit: model.beginLimitOrder,
                        onCancelOrder: onCancelOrder,
                        canCheckOrders: model.canCheckOrders(at:),
                        isCheckingOrders: model.isCheckingOrders,
                        orderCheckMessage: model.orderCheckMessage,
                        onCheckOrders: onCheckOrders,
                    )
                }
                .toolbar {
                    Button("Market Buy…", systemImage: "cart.badge.plus", action: model.beginPurchase)
                        .help("Buy shares of a ticker now at the market price")
                    Button("Buy Limit…", systemImage: "arrow.down.to.line", action: model.beginBuyLimitOrder)
                        .help("Place an order to buy shares once the price drops to a limit")
                }
                // On the detail, not beside the New Experiment sheet, so
                // each sheet has its own view.
                .sheet(isPresented: $model.isShowingPurchase) {
                    if let purchase = model.purchase {
                        PurchaseSheet(model: purchase, onBuy: onPurchase, onCancel: model.cancelPurchase)
                    }
                }
                .sheet(isPresented: $model.isShowingSale) {
                    if let sale = model.sale {
                        SaleSheet(model: sale, onSell: onSell, onCancel: model.cancelSale)
                    }
                }
                .sheet(isPresented: $model.isShowingBuyLimitOrder) {
                    if let buyLimitOrder = model.buyLimitOrder {
                        BuyLimitOrderSheet(
                            model: buyLimitOrder,
                            onPlace: onPlaceBuyLimitOrder,
                            onCancel: model.cancelBuyLimitOrder,
                        )
                    }
                }
                .sheet(isPresented: $model.isShowingLimitOrder) {
                    if let limitOrder = model.limitOrder {
                        LimitOrderSheet(
                            model: limitOrder,
                            onPlace: onPlaceLimitOrder,
                            onCancel: model.cancelLimitOrder,
                        )
                    }
                }
                .sheet(isPresented: $model.isShowingDetails) {
                    if let details = model.details {
                        ExperimentDetailsSheet(
                            model: details,
                            onSave: onSaveDetails,
                            onCancel: model.cancelEditingDetails,
                        )
                    }
                }
            case nil:
                ContentUnavailableView("No Selection", systemImage: "sidebar.left")
            }
        }
        // Tall enough for the fullest grouped-form sheet (about nine rows)
        // to fit without scrolling, and for both tables to keep a few rows
        // below the Experiment header (PIN-408).
        .frame(minWidth: 640, minHeight: 640)
        // Over the whole window, so it shows once the Market Buy or Market Sell sheet closes.
        .overlay(ConfettiView(trigger: model.celebrationCount))
        // Cancelling the new experiment closes the new, untitled document.
        .background(WindowCloser(isClosing: model.shouldCloseWindow))
        .sheet(isPresented: $model.isShowingNewExperiment) {
            NewExperimentSheet(
                model: model.newExperiment,
                onCreate: onCreate,
                onCancel: model.cancelNewExperiment,
            )
        }
    }
}

private extension NavigationSection {
    var systemImage: String {
        switch self {
        case .experiment: "flask"
        }
    }
}
