import Foundation
import InvestmentSimulatorCore

/// Core doesn't format display strings, so the adapters describe the errors
/// they raise.
extension MarketDataError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your Equibles API key in Settings to see this."
        case .invalidAPIKey:
            "Equibles didn't accept the API key. Check it in Settings."
        case .dailyLimitReached:
            "You've reached today's Equibles request limit. It resets at midnight UTC."
        case let .unavailable(detail):
            "Couldn't load this. \(detail)"
        case .noData:
            "Equibles has no data for this ticker."
        case .missingContactEmail:
            "Add your SEC contact email in Settings to see this."
        }
    }
}
