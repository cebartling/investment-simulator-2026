import Foundation
import InvestmentSimulatorCore
import Testing

struct DailyBarTests {
    @Test func `bar keeps its session and prices`() throws {
        let bar = try makeDailyBar(
            session: "2026-10-23",
            open: "349.115",
            high: "351.73",
            low: "345.75",
            close: "347.725",
        )

        #expect(bar.sessionDate == "2026-10-23")
        #expect(try bar.open == #require(Decimal(string: "349.115")))
        #expect(try bar.high == #require(Decimal(string: "351.73")))
        #expect(try bar.low == #require(Decimal(string: "345.75")))
        #expect(try bar.close == #require(Decimal(string: "347.725")))
    }

    @Test(arguments: ["", "2026-10-2", "10/23/2026", "2026-10-23T16:00"])
    func `session date must be yyyy-MM-dd`(session: String) {
        #expect(throws: DailyBarError.invalidSessionDate(session)) {
            try makeDailyBar(session: session)
        }
    }

    @Test(arguments: ["0", "-1"])
    func `low must be positive`(low: String) throws {
        let price = try #require(Decimal(string: low))

        #expect(throws: DailyBarError.nonPositivePrice(price)) {
            try makeDailyBar(open: "10", high: "10", low: low, close: "10")
        }
    }

    @Test(arguments: [
        ("9", "12", "10", "11"),
        ("13", "12", "10", "11"),
        ("11", "12", "10", "9"),
        ("11", "12", "10", "13"),
        ("11", "10", "12", "11"),
    ])
    func `open and close must lie between low and high`(open: String, high: String, low: String, close: String) {
        #expect(throws: DailyBarError.inconsistentPrices) {
            try makeDailyBar(open: open, high: high, low: low, close: close)
        }
    }
}

func makeDailyBar(
    session: String = "2026-10-23",
    open: String = "11",
    high: String = "12",
    low: String = "10",
    close: String = "11",
) throws -> DailyBar {
    try DailyBar(
        sessionDate: session,
        open: #require(Decimal(string: open)),
        high: #require(Decimal(string: high)),
        low: #require(Decimal(string: low)),
        close: #require(Decimal(string: close)),
    )
}
