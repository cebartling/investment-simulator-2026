import InvestmentSimulatorPresentation
import SwiftUI

struct ContentView: View {
    @Bindable var model: MainWindowModel
    let onCreate: () -> Void
    let onPurchase: () -> Void

    var body: some View {
        NavigationSplitView {
            List(model.sections, selection: $model.selection) { section in
                Label(section.title, systemImage: section.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch model.selection {
            case .experiment:
                ExperimentDetailView(cashBalance: model.cashBalance, purchases: model.purchases)
                    .toolbar {
                        Button("Buy…", systemImage: "cart.badge.plus", action: model.beginPurchase)
                    }
                    // On the detail, not beside the New Experiment sheet, so
                    // each sheet has its own view.
                    .sheet(isPresented: $model.isShowingPurchase) {
                        if let purchase = model.purchase {
                            PurchaseSheet(model: purchase, onBuy: onPurchase, onCancel: model.cancelPurchase)
                        }
                    }
            case let section?:
                ContentUnavailableView(section.title, systemImage: section.systemImage)
            case nil:
                ContentUnavailableView("No Selection", systemImage: "sidebar.left")
            }
        }
        .frame(minWidth: 640, minHeight: 400)
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
        case .simulation: "play.circle"
        case .results: "chart.line.uptrend.xyaxis"
        }
    }
}
