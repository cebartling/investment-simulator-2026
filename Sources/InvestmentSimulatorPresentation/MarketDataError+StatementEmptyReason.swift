import InvestmentSimulatorCore

extension MarketDataError {
    /// What a statement says when it fails with this error and a retry
    /// couldn't help; nil for an error worth retrying.
    nonisolated var statementEmptyReason: ResearchEmptyReason? {
        switch self {
        case .noData: .noData
        case .unsupportedCurrency: .unsupportedCurrency
        default: nil
        }
    }
}
