import Foundation
import InvestmentSimulatorCore

/// Each request returns one statement for one period. With no period,
/// Equibles sends the latest (ADR-0019).
extension EquiblesResearchProvider: FinancialStatementProviding {
    /// As with press releases, a line that can't be read is left out, unless
    /// that leaves none. A line in another currency, which `Money` can't
    /// hold, is left out the same way; if every line is, the statement is
    /// `unsupportedCurrency`, not unreadable, because a retry can't fix it.
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
        guard let year = response.fiscalYear, let part = part(named: response.fiscalPeriod) else {
            throw .unreadableResponse
        }
        let lines = response.data.compactMap(line(from:))
        guard !lines.isEmpty else {
            // Retrying can't make another currency readable.
            let allOtherCurrency = response.data.allSatisfy { unit(of: $0) == .otherCurrency }
            throw allOtherCurrency ? .unsupportedCurrency : .unreadableResponse
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
        case .quarter1: "Q1"
        case .quarter2: "Q2"
        case .quarter3: "Q3"
        case .quarter4: "Q4"
        case .fullYear: "FY"
        }
    }

    private func part(named name: String?) -> FiscalPeriod.Part? {
        switch name {
        case "Q1": .quarter1
        case "Q2": .quarter2
        case "Q3": .quarter3
        case "Q4": .quarter4
        case "FY": .fullYear
        default: nil
        }
    }

    private enum Unit {
        case money, perShare, shares
        /// A currency code, alone or per share, that `Money` can't hold.
        case otherCurrency
    }

    /// Nil for a unit that isn't a currency or a count of shares, which is
    /// unreadable rather than unsupported.
    private func unit(of row: StatementResponse.Row) -> Unit? {
        switch row.unit {
        case "USD": return .money
        case "USD/shares": return .perShare
        case "shares": return .shares
        case let unit?:
            let code = unit.hasSuffix("/shares") ? String(unit.dropLast("/shares".count)) : unit
            let isCode = code.count == 3 && code.allSatisfy { $0.isASCII && $0.isUppercase }
            return isCode ? .otherCurrency : nil
        case nil: return nil
        }
    }

    private func line(from row: StatementResponse.Row) -> StatementLine? {
        guard let name = row.lineItem, let number = row.value, let value = try? requiredDecimal(from: number) else {
            return nil
        }
        switch unit(of: row) {
        case .money: return StatementLine(name: name, figure: .money(Money(value)))
        case .perShare: return StatementLine(name: name, figure: .perShare(value))
        case .shares: return StatementLine(name: name, figure: .shares(value))
        case .otherCurrency, nil: return nil
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
