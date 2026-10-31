import InvestmentSimulatorCore
import Testing

struct SecurityDirectoryTests {
    private func security(_ symbol: String, _ name: String, _ exchange: String? = "Nasdaq") throws -> ListedSecurity {
        try ListedSecurity(ticker: Ticker(symbol), name: name, exchange: exchange)
    }

    @Test func `matches a name or symbol in any case`() throws {
        let apple = try security("AAPL", "Apple Inc.")
        let list = try [security("MSFT", "MICROSOFT CORP"), apple]

        #expect(list.matching("apple") == [apple])
        #expect(list.matching("aapl") == [apple])
    }

    @Test func `ranks exact symbol, symbol prefix, name prefix, then name contains`() throws {
        let contains = try security("ZZZ", "Big Meta Corp")
        let namePrefix = try security("YYY", "Meta Platforms, Inc.")
        let symbolPrefix = try security("METAX", "Xylem Holdings")
        let exact = try security("META", "Other Co")
        let list = [contains, namePrefix, symbolPrefix, exact]

        #expect(list.matching("meta") == [exact, symbolPrefix, namePrefix, contains])
    }

    @Test func `keeps the list's order within a rank`() throws {
        let first = try security("AAA", "Acme One")
        let second = try security("BBB", "Acme Two")

        #expect([first, second].matching("acme") == [first, second])
    }

    @Test func `blank text matches nothing`() throws {
        let list = try [security("AAPL", "Apple Inc.")]

        #expect(list.matching("").isEmpty)
        #expect(list.matching("   ").isEmpty)
    }

    @Test func `surrounding spaces are ignored, and spaces within a name kept`() throws {
        let apple = try security("AAPL", "Apple Inc.")

        #expect([apple].matching("  apple inc ") == [apple])
    }

    @Test func `search treats dots and dashes in a symbol alike`() throws {
        let berkshire = try security("BRK-B", "BERKSHIRE HATHAWAY INC", "NYSE")

        #expect([berkshire].matching("brk.b") == [berkshire])
    }

    @Test func `at most twenty matches come back, the best ones`() throws {
        let weak = try (0 ..< 25).map { try security("X\($0)", "Acme \($0)") }
        let exact = try security("ACME", "Other Co")

        let matches = (weak + [exact]).matching("acme")

        #expect(matches.count == 20)
        #expect(matches.first == exact)
    }

    @Test func `a lookup treats dots and dashes in a symbol alike`() throws {
        let berkshire = try security("BRK-B", "BERKSHIRE HATHAWAY INC", "NYSE")

        #expect(try [berkshire].security(for: Ticker("BRK.B")) == berkshire)
        #expect(try [berkshire].security(for: Ticker("BRK-B")) == berkshire)
    }

    @Test func `a lookup of an unlisted ticker finds nothing`() throws {
        let list = try [security("AAPL", "Apple Inc.")]

        #expect(try list.security(for: Ticker("VTI")) == nil)
    }
}
