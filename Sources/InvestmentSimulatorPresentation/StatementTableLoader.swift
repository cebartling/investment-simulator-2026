import InvestmentSimulatorCore

/// The statement and cadence a Research tab shows.
public nonisolated struct StatementSelection: Hashable, Sendable {
    public let kind: StatementKind
    public let cadence: StatementCadence

    public init(kind: StatementKind, cadence: StatementCadence) {
        self.kind = kind
        self.cadence = cadence
    }
}

/// Builds a statement table from Equibles' one period per request (ADR-0019).
nonisolated struct StatementTableLoader {
    let statements: any FinancialStatementProviding
    let ticker: Ticker

    func latest(_ kind: StatementKind) async throws(MarketDataError) -> FinancialStatement {
        try await statements.financialStatement(kind, for: ticker, period: nil)
    }

    /// Asks for the periods walked back from `latest`, all at once. A period
    /// Equibles doesn't have loses its column, as a new company's would. Any
    /// other failure fails the table, which mustn't look complete without it.
    func table(
        _ selection: StatementSelection,
        endingAt latest: FinancialStatement,
    ) async throws(MarketDataError) -> StatementTable {
        let periods = FiscalPeriod.periods(endingAt: latest.period, cadence: selection.cadence)
        let answers = await withTaskGroup { group in
            for period in periods where period != latest.period {
                group.addTask { await (period, answer(selection.kind, period)) }
            }
            return await group.reduce(into: [FiscalPeriod: Result<FinancialStatement?, MarketDataError>]()) {
                $0[$1.0] = $1.1
            }
        }
        var found: [FinancialStatement] = []
        for period in periods {
            if period == latest.period {
                found.append(latest)
            } else if let statement = try answers[period]?.get() {
                found.append(statement)
            }
        }
        guard !found.isEmpty else {
            throw .noData
        }
        return StatementTable(statements: found)
    }

    private func answer(
        _ kind: StatementKind,
        _ period: FiscalPeriod,
    ) async -> Result<FinancialStatement?, MarketDataError> {
        do throws(MarketDataError) {
            return try await .success(statements.financialStatement(kind, for: ticker, period: period))
        } catch .noData {
            return .success(nil)
        } catch {
            return .failure(error)
        }
    }
}
