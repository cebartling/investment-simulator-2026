import InvestmentSimulatorCore
import Testing

struct AppMetadataTests {
    @Test func `display name is investment simulator`() {
        #expect(AppMetadata.displayName == "Investment Simulator")
    }
}
