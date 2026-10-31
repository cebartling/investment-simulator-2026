import InvestmentSimulatorCore

/// The ports behind a ticker's Research sections (ADR-0019), passed down
/// together. Each stays its own port, so a test can fake one alone.
public nonisolated struct ResearchSectionPorts: Sendable {
    let profiles: any CompanyProfileProviding
    let multiples: any ValuationMultiplesProviding
    let dividends: any DividendProviding
    let pressReleases: any PressReleaseProviding
    let filings: any FilingProviding

    public init(
        profiles: any CompanyProfileProviding,
        multiples: any ValuationMultiplesProviding,
        dividends: any DividendProviding,
        pressReleases: any PressReleaseProviding,
        filings: any FilingProviding,
    ) {
        self.profiles = profiles
        self.multiples = multiples
        self.dividends = dividends
        self.pressReleases = pressReleases
        self.filings = filings
    }
}
