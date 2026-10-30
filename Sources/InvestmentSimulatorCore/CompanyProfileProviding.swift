/// Who a ticker's company is.
public struct CompanyProfile: Sendable, Hashable {
    public let name: String
    public let sector: String?
    public let industry: String?
    /// As reported, which can include fractions of a cent.
    public let marketCap: Money?

    public init(name: String, sector: String?, industry: String?, marketCap: Money?) {
        self.name = name
        self.sector = sector
        self.industry = industry
        self.marketCap = marketCap
    }
}

/// Driven port for a ticker's company profile (ADR-0019). `async` because
/// adapters reach the network (ADR-0003).
public protocol CompanyProfileProviding: Sendable {
    func companyProfile(for ticker: Ticker) async throws(MarketDataError) -> CompanyProfile
}
