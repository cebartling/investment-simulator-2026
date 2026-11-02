import Foundation
import InvestmentSimulatorCore

/// Buying from Research (ADR-0020).
public extension MainWindowModel {
    /// True while any of this window's sheets shows. Research can't start a
    /// purchase then, as that would replace what the user is typing.
    var isShowingSheet: Bool {
        isShowingNewExperiment || isShowingPurchase || isShowingSale
            || isShowingLimitOrder || isShowingBuyLimitOrder || isShowingDetails
    }

    func beginPurchase(of ticker: Ticker) {
        handOff {
            beginPurchase()
            purchase?.tickerText = ticker.symbol
        }
    }

    func beginBuyLimitOrder(of ticker: Ticker) {
        handOff {
            beginBuyLimitOrder()
            buyLimitOrder?.tickerText = ticker.symbol
        }
    }

    /// Does nothing while a sheet shows. The sheets live in the Experiment
    /// section, so it selects that first.
    private func handOff(showSheet: () -> Void) {
        guard !isShowingSheet else {
            return
        }
        selection = .experiment
        showSheet()
        raiseCount += 1
    }
}
