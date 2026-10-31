import Foundation
import InvestmentSimulatorCore

/// Each request returns one statement for one period. With no period,
/// Equibles sends the latest (ADR-0019).
extension EquiblesResearchProvider: FinancialStatementProviding {
    /// As with press releases, a line that can't be read is left out, unless
    /// that leaves none. That includes a line in another currency, which
    /// `Money` can't hold.
    public func financialStatement(
        _ kind: StatementKind,
        for ticker: Ticker,
        period: FiscalPeriod?,
    ) async throws(MarketDataError) -> FinancialStatement {
        var url = baseURL.appending(path: "stocks/\(ticker.symbol)/financial-statements/\(pathComponent(of: kind))")
        if let period {
            url = url.appending(queryItems: [
                URLQueryItem(name: "year", value: String(period.year)),
                URLQueryItem(name: "period", value: name(of: period.part)),
            ])
        }
        let response = try await get(StatementResponse.self, from: url)
        guard !response.data.isEmpty else {
            throw .noData
        }
        let lines = response.data.compactMap(line(from:))
        guard !lines.isEmpty, let year = response.fiscalYear, let part = part(named: response.fiscalPeriod) else {
            throw .unreadableResponse
        }
        return FinancialStatement(period: FiscalPeriod(year: year, part: part), lines: lines)
    }

    private func pathComponent(of kind: StatementKind) -> String {
        switch kind {
        case .income: "income"
        case .balance: "balance"
        case .cashFlow: "cashflow"
        }
    }

    private func name(of part: FiscalPeriod.Part) -> String {
        switch part {
        case .q1: "Q1"
        case .q2: "Q2"
        case .q3: "Q3"
        case .q4: "Q4"
        case .fullYear: "FY"
        }
    }

    private func part(named name: String?) -> FiscalPeriod.Part? {
        switch name {
        case "Q1": .q1
        case "Q2": .q2
        case "Q3": .q3
        case "Q4": .q4
        case "FY": .fullYear
        default: nil
        }
    }

    private func line(from row: StatementResponse.Row) -> StatementLine? {
        guard let name = row.lineItem, let number = row.value, let value = try? requiredDecimal(from: number) else {
            return nil
        }
        switch row.unit {
        case "USD": return StatementLine(name: name, figure: .money(Money(value)))
        case "USD/shares": return StatementLine(name: name, figure: .perShare(value))
        case "shares": return StatementLine(name: name, figure: .shares(value))
        default: return nil
        }
    }
}

private struct StatementResponse: Decodable {
    /// All optional, so a line with a missing field is left out on its own
    /// and doesn't fail the decoding of the statement.
    struct Row: Decodable {
        let lineItem: String?
        let value: Double?
        let unit: String?
    }

    let fiscalYear: Int?
    let fiscalPeriod: String?
    let data: [Row]
}
