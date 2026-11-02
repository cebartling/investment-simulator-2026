import InvestmentSimulatorCore

extension MarketDataError {
    /// What a section says when it fails with this error and a retry
    /// couldn't help; nil for an error worth retrying.
    nonisolated var emptyReason: ResearchEmptyReason? {
        switch self {
        case .noData: .noData
        case .unsupportedCurrency: .unsupportedCurrency
        default: nil
        }
    }

    /// How a section shows this failure: an empty state when a retry
    /// couldn't help, otherwise the error.
    nonisolated func sectionState<Value>() -> ResearchSectionState<Value> {
        emptyReason.map { .empty($0) } ?? .failed(self)
    }
}
