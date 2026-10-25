import InvestmentSimulatorCore
import Testing

struct TickerTests {
    @Test(arguments: [
        ("VTI", "VTI"),
        ("vti", "VTI"),
        ("  aapl ", "AAPL"),
        ("BRK.B", "BRK.B"),
        ("BRK-A", "BRK-A"),
    ])
    func `ticker is trimmed and uppercased`(entered: String, symbol: String) throws {
        #expect(try Ticker(entered).symbol == symbol)
    }

    @Test(arguments: [
        "", "   ", "VT I", "VTI$", "ÅAPL", ".", "..", "-", ".VTI", "-A", String(repeating: "A", count: 33),
    ])
    func `invalid ticker is rejected`(entered: String) {
        #expect(throws: TickerError.invalid(entered)) {
            try Ticker(entered)
        }
    }

    @Test func `ticker can be 32 characters long`() throws {
        let symbol = String(repeating: "A", count: 32)

        #expect(try Ticker(symbol).symbol == symbol)
    }
}
