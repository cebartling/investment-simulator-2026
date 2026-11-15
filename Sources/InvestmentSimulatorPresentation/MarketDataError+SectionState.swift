import InvestmentSimulatorCore

extension MarketDataError {
    /// Why a section, or a statement period, has nothing to show when it
    /// fails with this error and a retry couldn't help; nil for an error
    /// worth retrying. Every case is listed, so a new one must be decided.
    nonisolated var emptyReason: ResearchEmptyReason? {
        switch self {
        case .noData: .noData
        case .unsupportedCurrency: .unsupportedCurrency
        case .missingAPIKey, .invalidAPIKey, .dailyLimitReached, .unavailable, .missingContactEmail: nil
        }
    }

    /// How a section shows this failure: an empty state when a retry
    /// couldn't help, otherwise the error.
    nonisolated func sectionState<Value>() -> ResearchSectionState<Value> {
        guard let emptyReason else {
            return .failed(self)
        }
        return .empty(emptyReason)
    }
}
