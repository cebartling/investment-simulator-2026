import InvestmentSimulatorPresentation
import SwiftUI

/// One experiment in the library window's detail: its header, stock cards
/// (PIN-510) and footer, and the sheets that change it. The model saves
/// each change itself (ADR-0021).
struct ExperimentView: View {
    @Bindable var model: MainWindowModel

    var body: some View {
        VStack(spacing: 0) {
            if model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError = model.loadError {
                ContentUnavailableView(
                    "Couldn't Open This Experiment",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError),
                )
            } else {
                experiment
                Divider()
                ExperimentFooter(model: model)
            }
        }
        // Over the whole detail, so it shows once the Market Buy or Market Sell sheet closes.
        .overlay(ConfettiView(trigger: model.celebrationCount))
    }

    private var experiment: some View {
        VStack(spacing: 16) {
            ExperimentHeader(
                model: model,
                title: model.title,
                onEditDetails: model.beginEditingDetails,
            )
            .padding(.top, 16)
            StockCardList(model: model)
        }
        // On the detail, not beside the New Experiment sheet, so
        // each sheet has its own view.
        .sheet(isPresented: $model.isShowingPurchase) {
            if let purchase = model.purchase {
                PurchaseSheet(model: purchase, onBuy: { model.completePurchase() }, onCancel: model.cancelPurchase)
            }
        }
        .sheet(isPresented: $model.isShowingSale) {
            if let sale = model.sale {
                SaleSheet(model: sale, onSell: { model.completeSale() }, onCancel: model.cancelSale)
            }
        }
        .sheet(isPresented: $model.isShowingBuyLimitOrder) {
            if let buyLimitOrder = model.buyLimitOrder {
                BuyLimitOrderSheet(
                    model: buyLimitOrder,
                    onPlace: { model.completeBuyLimitOrder() },
                    onCancel: model.cancelBuyLimitOrder,
                )
            }
        }
        .sheet(isPresented: $model.isShowingLimitOrder) {
            if let limitOrder = model.limitOrder {
                LimitOrderSheet(
                    model: limitOrder,
                    onPlace: { model.completeLimitOrder() },
                    onCancel: model.cancelLimitOrder,
                )
            }
        }
        .sheet(isPresented: $model.isShowingDetails) {
            if let details = model.details {
                ExperimentDetailsSheet(
                    model: details,
                    onSave: { model.completeEditingDetails() },
                    onCancel: model.cancelEditingDetails,
                )
            }
        }
    }
}
