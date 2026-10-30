import Foundation

/// One valuation ratio beside its industry peers. Any figure can be missing:
/// a ratio may not be computable, and peers need at least three companies.
public struct ValuationRatio: Sendable, Hashable {
    public let value: Decimal?
    public let peerMedian: Decimal?
    public let peerP25: Decimal?
    public let peerP75: Decimal?

    public init(value: Decimal?, peerMedian: Decimal?, peerP25: Decimal?, peerP75: Decimal?) {
        self.value = value
        self.peerMedian = peerMedian
        self.peerP25 = peerP25
        self.peerP75 = peerP75
    }
}

/// A ticker's valuation ratios.
public struct ValuationMultiples: Sendable, Hashable {
    public let peRatio: ValuationRatio
    public let evToRevenue: ValuationRatio
    public let evToEbit: ValuationRatio

    public init(peRatio: ValuationRatio, evToRevenue: ValuationRatio, evToEbit: ValuationRatio) {
        self.peRatio = peRatio
        self.evToRevenue = evToRevenue
        self.evToEbit = evToEbit
    }
}

/// Driven port for a ticker's valuation multiples (ADR-0019). `async`
/// because adapters reach the network (ADR-0003).
public protocol ValuationMultiplesProviding: Sendable {
    func valuationMultiples(for ticker: Ticker) async throws(MarketDataError) -> ValuationMultiples
}
