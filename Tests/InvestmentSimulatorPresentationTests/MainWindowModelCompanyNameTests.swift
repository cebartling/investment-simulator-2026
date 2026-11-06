import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// The company names on the stock cards (PIN-510).
extension MainWindowModelTests {
    @Test func `a ticker's company name loads once`() async throws {
        let profiles = FakeResearchData(profile: .success(Self.vanguard))
        let model = try await makeModel(profiles: profiles)

        try await model.loadCompanyName(of: Ticker("VTI"))
        try await model.loadCompanyName(of: Ticker("VTI"))

        #expect(try model.companyNames[Ticker("VTI")] == "Vanguard Total Stock Market ETF")
        #expect(profiles.requestCount == 1)
    }

    @Test func `a ticker with no profile has no name and isn't asked again`() async throws {
        let profiles = FakeResearchData(profile: .failure(.noData))
        let model = try await makeModel(profiles: profiles)

        try await model.loadCompanyName(of: Ticker("VTI"))
        try await model.loadCompanyName(of: Ticker("VTI"))

        #expect(model.companyNames.isEmpty)
        #expect(profiles.requestCount == 1)
    }

    @Test func `a name that failed to load is asked for again the next time`() async throws {
        let profiles = FakeResearchData(profile: .failure(.missingAPIKey))
        let model = try await makeModel(profiles: profiles)

        try await model.loadCompanyName(of: Ticker("VTI"))
        try await model.loadCompanyName(of: Ticker("VTI"))

        #expect(model.companyNames.isEmpty)
        #expect(profiles.requestCount == 2)
    }

    private static let vanguard = CompanyProfile(
        name: "Vanguard Total Stock Market ETF",
        sector: nil,
        industry: nil,
        marketCap: nil,
    )

    private func makeModel(profiles: FakeResearchData) async throws -> MainWindowModel {
        try await loadedModel(
            experiment: Experiment(cashBalance: Money(100)),
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: FakeDailyPrices(),
            profiles: profiles,
        )
    }
}
