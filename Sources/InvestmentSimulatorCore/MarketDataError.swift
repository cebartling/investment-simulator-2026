/// Why a Research section's port failed (ADR-0019). Apart from `QuoteError`,
/// because a `404` here doesn't mean an unknown ticker.
public enum MarketDataError: Error, Equatable {
    case missingAPIKey
    case invalidAPIKey
    case dailyLimitReached
    /// Any other failure, with a detail for debugging.
    case unavailable(String)
    /// Nothing to show for a ticker the quote has already validated. An
    /// empty state, not an error.
    case noData
}
