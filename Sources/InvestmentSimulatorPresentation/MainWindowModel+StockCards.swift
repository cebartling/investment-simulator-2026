import Foundation
import InvestmentSimulatorCore

/// The stock cards (PIN-510).
public extension MainWindowModel {
    /// Loads the company name of `ticker` into `companyNames` the first
    /// time it is asked for, as each card appears. Until then, and when it
    /// can't load, the card shows the ticker alone. A ticker with no profile
    /// isn't asked for again; any other failure, such as a missing API key,
    /// is, the next time the card appears.
    func loadCompanyName(of ticker: Ticker) async {
        guard companyNameRequests.insert(ticker).inserted else {
            return
        }
        do throws(MarketDataError) {
            companyNames[ticker] = try await profiles.companyProfile(for: ticker).name
        } catch .noData {
            // No name to show, now or later.
        } catch {
            companyNameRequests.remove(ticker)
        }
    }
}
