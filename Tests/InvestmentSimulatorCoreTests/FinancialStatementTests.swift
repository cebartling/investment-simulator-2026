import Foundation
import InvestmentSimulatorCore
import Testing

struct FinancialStatementTests {
    private static let quarter3 = FiscalPeriod(year: 2026, part: .quarter3)
    private static let fy25 = FiscalPeriod(year: 2025, part: .fullYear)
    private static let quarter4 = FiscalPeriod(year: 2025, part: .quarter4)

    private static func line(_ name: String, _ amount: Decimal) -> StatementLine {
        StatementLine(name: name, figure: .money(Money(amount)))
    }

    @Test func `quarters walk back across the year`() {
        let periods = FiscalPeriod.periods(endingAt: Self.quarter3, cadence: .quarterly)

        #expect(periods == [
            FiscalPeriod(year: 2026, part: .quarter3),
            FiscalPeriod(year: 2026, part: .quarter2),
            FiscalPeriod(year: 2026, part: .quarter1),
            FiscalPeriod(year: 2025, part: .quarter4),
        ])
    }

    @Test func `the first quarter walks back into the year before`() {
        let periods = FiscalPeriod.periods(endingAt: FiscalPeriod(year: 2026, part: .quarter1), cadence: .quarterly)

        #expect(periods == [
            FiscalPeriod(year: 2026, part: .quarter1),
            FiscalPeriod(year: 2025, part: .quarter4),
            FiscalPeriod(year: 2025, part: .quarter3),
            FiscalPeriod(year: 2025, part: .quarter2),
        ])
    }

    @Test func `the fourth quarter walks back through its own year`() {
        let periods = FiscalPeriod.periods(endingAt: Self.quarter4, cadence: .quarterly)

        #expect(periods.first == Self.quarter4)
        #expect(periods.last == FiscalPeriod(year: 2025, part: .quarter1))
    }

    @Test func `a finished year's quarters start at its fourth quarter`() {
        let periods = FiscalPeriod.periods(endingAt: Self.fy25, cadence: .quarterly)

        #expect(periods == [
            FiscalPeriod(year: 2025, part: .quarter4),
            FiscalPeriod(year: 2025, part: .quarter3),
            FiscalPeriod(year: 2025, part: .quarter2),
            FiscalPeriod(year: 2025, part: .quarter1),
        ])
    }

    @Test func `years skip the year still under way`() {
        let periods = FiscalPeriod.periods(endingAt: Self.quarter3, cadence: .annual)

        #expect(periods == [
            FiscalPeriod(year: 2025, part: .fullYear),
            FiscalPeriod(year: 2024, part: .fullYear),
            FiscalPeriod(year: 2023, part: .fullYear),
        ])
    }

    @Test func `years start at a finished year`() {
        let periods = FiscalPeriod.periods(endingAt: Self.fy25, cadence: .annual)

        #expect(periods == [
            FiscalPeriod(year: 2025, part: .fullYear),
            FiscalPeriod(year: 2024, part: .fullYear),
            FiscalPeriod(year: 2023, part: .fullYear),
        ])
    }

    @Test func `years start at the year a fourth quarter ends`() {
        let periods = FiscalPeriod.periods(endingAt: Self.quarter4, cadence: .annual)

        #expect(periods.first == Self.fy25)
    }

    @Test func `a table puts each period's figures in its own column`() {
        let table = StatementTable(statements: [
            FinancialStatement(period: Self.quarter3, lines: [Self.line("Revenue", 2)]),
            FinancialStatement(period: Self.quarter4, lines: [Self.line("Revenue", 1)]),
        ])

        #expect(table.periods == [Self.quarter3, Self.quarter4])
        #expect(table.rows == [
            StatementRow(name: "Revenue", figures: [.money(Money(2)), .money(Money(1))]),
        ])
    }

    @Test func `a line a period lacks leaves that cell empty`() {
        let eps = StatementLine(name: "EPS (Basic)", figure: .perShare(2))
        let table = StatementTable(statements: [
            FinancialStatement(period: Self.quarter3, lines: [Self.line("Revenue", 2), eps]),
            FinancialStatement(period: Self.quarter4, lines: [Self.line("Revenue", 1)]),
        ])

        #expect(table.rows[1] == StatementRow(name: "EPS (Basic)", figures: [.perShare(2), nil]))
    }

    @Test func `a line only an older period has joins the end`() {
        let table = StatementTable(statements: [
            FinancialStatement(period: Self.quarter4, lines: [Self.line("Revenue", 1)]),
            FinancialStatement(period: Self.quarter3, lines: [Self.line("Revenue", 2), Self.line("EPS", 3)]),
        ])

        #expect(table.rows.map(\.name) == ["Revenue", "EPS"])
        #expect(table.rows[1].figures == [nil, .money(Money(3))])
    }

    @Test func `a line named twice in a period keeps its first figure`() {
        let table = StatementTable(statements: [
            FinancialStatement(period: Self.quarter3, lines: [Self.line("Revenue", 2), Self.line("Revenue", 9)]),
        ])

        #expect(table.rows == [StatementRow(name: "Revenue", figures: [.money(Money(2))])])
    }
}
