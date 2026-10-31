import Foundation

public enum StatementKind: Sendable, Hashable, CaseIterable {
    case income
    case balance
    case cashFlow
}

public enum StatementCadence: Sendable, Hashable, CaseIterable {
    case quarterly
    case annual
}

/// A quarter or a whole year of a company's fiscal calendar.
public struct FiscalPeriod: Sendable, Hashable {
    public enum Part: Sendable, Hashable {
        case quarter1
        case quarter2
        case quarter3
        case quarter4
        case fullYear
    }

    private static let quarters: [Part] = [.quarter1, .quarter2, .quarter3, .quarter4]
    private static let quartersShown = 4
    private static let yearsShown = 3

    public let year: Int
    public let part: Part

    public init(year: Int, part: Part) {
        self.year = year
        self.part = part
    }

    /// The periods a table shows, newest first, given the latest one a
    /// statement has. No endpoint lists them, so they're worked out from it
    /// (ADR-0019). A company's latest period can be a whole year: Equibles
    /// reports that year's fourth quarter only when asked for it.
    public static func periods(endingAt latest: FiscalPeriod, cadence: StatementCadence) -> [FiscalPeriod] {
        switch cadence {
        case .quarterly:
            let newest = latest.year * quarters.count + (quarters.firstIndex(of: latest.part) ?? quarters.count - 1)
            return (0 ..< quartersShown).map { offset in
                let index = newest - offset
                return FiscalPeriod(year: index / quarters.count, part: quarters[index % quarters.count])
            }
        case .annual:
            let finished = [.quarter4, .fullYear].contains(latest.part)
            let newest = finished ? latest.year : latest.year - 1
            return (0 ..< yearsShown).map { FiscalPeriod(year: newest - $0, part: .fullYear) }
        }
    }
}

/// One figure on a statement, in the unit its line is reported in.
public enum StatementFigure: Sendable, Hashable {
    case money(Money)
    case perShare(Decimal)
    case shares(Decimal)
}

public struct StatementLine: Sendable, Hashable {
    public let name: String
    public let figure: StatementFigure

    public init(name: String, figure: StatementFigure) {
        self.name = name
        self.figure = figure
    }
}

/// One statement for one fiscal period.
public struct FinancialStatement: Sendable, Hashable {
    public let period: FiscalPeriod
    public let lines: [StatementLine]

    public init(period: FiscalPeriod, lines: [StatementLine]) {
        self.period = period
        self.lines = lines
    }
}

/// One line across a table's periods. A period that lacks the line, as a
/// derived fourth quarter lacks EPS, has a nil figure.
public struct StatementRow: Sendable, Hashable {
    public let name: String
    public let figures: [StatementFigure?]

    public init(name: String, figures: [StatementFigure?]) {
        self.name = name
        self.figures = figures
    }
}

/// One statement across several periods, a column each.
public struct StatementTable: Sendable, Hashable {
    public let periods: [FiscalPeriod]
    public let rows: [StatementRow]

    /// Takes `statements` in column order. Lines keep the order they're first
    /// met in.
    public init(statements: [FinancialStatement]) {
        periods = statements.map(\.period)
        let columns = statements.map { statement in
            Dictionary(statement.lines.map { ($0.name, $0.figure) }, uniquingKeysWith: { first, _ in first })
        }
        var seen = Set<String>()
        let names = statements.flatMap(\.lines).map(\.name).filter { seen.insert($0).inserted }
        rows = names.map { name in
            StatementRow(name: name, figures: columns.map { $0[name] })
        }
    }
}

/// Driven port for a ticker's financial statements (ADR-0019). `async`
/// because adapters reach the network (ADR-0003).
public protocol FinancialStatementProviding: Sendable {
    /// One statement for one period, or the latest one when `period` is nil.
    func financialStatement(
        _ kind: StatementKind,
        for ticker: Ticker,
        period: FiscalPeriod?,
    ) async throws(MarketDataError) -> FinancialStatement
}
