import InvestmentSimulatorCore
import Testing

struct AppMetadataTests {
    @Test func displayNameIsInvestmentSimulator() {
        #expect(AppMetadata.displayName == "Investment Simulator")
    }
}
