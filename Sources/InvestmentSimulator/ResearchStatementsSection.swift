import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// A company's statements, closed until asked for: each table costs several
/// requests (ADR-0019). The open state lives on the tab, because this view
/// is reused from one ticker to the next.
struct ResearchStatementsSection: View {
    let tab: ResearchTabModel
    let onShow: @MainActor (StatementSelection) -> Void
    let onHide: @MainActor () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { tab.statementsShown },
            set: { $0 ? onShow(tab.statementSelection) : onHide() },
        )) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("Statement", selection: kind) {
                        ForEach(StatementKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Cadence", selection: cadence) {
                        ForEach(StatementCadence.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                ResearchSectionContent(
                    state: tab.statementState,
                    ticker: tab.ticker,
                    subject: "financial statements",
                    // A failed table isn't kept, so showing it again retries it.
                    onRetry: { onShow(tab.statementSelection) },
                    content: ResearchStatementTableView.init,
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            Text("Financial Statements")
                .font(.headline)
        }
    }

    private var kind: Binding<StatementKind> {
        Binding(
            get: { tab.statementSelection.kind },
            set: { onShow(StatementSelection(kind: $0, cadence: tab.statementSelection.cadence)) },
        )
    }

    private var cadence: Binding<StatementCadence> {
        Binding(
            get: { tab.statementSelection.cadence },
            set: { onShow(StatementSelection(kind: tab.statementSelection.kind, cadence: $0)) },
        )
    }
}

/// One statement, with a column per period, newest first.
struct ResearchStatementTableView: View {
    let table: StatementTable

    var body: some View {
        let formatter = ResearchFigureFormatter()
        Grid(alignment: .trailing, horizontalSpacing: 20, verticalSpacing: 4) {
            GridRow {
                Text("Line Item")
                    .gridColumnAlignment(.leading)
                ForEach(table.periods, id: \.self) { Text(formatter.period($0)) }
            }
            .foregroundStyle(.secondary)
            ForEach(table.rows, id: \.name) { row in
                GridRow {
                    Text(row.name)
                    // By position: a period can lack a figure, or match another.
                    ForEach(Array(row.figures.enumerated()), id: \.offset) { _, figure in
                        Text(formatter.statementFigure(figure))
                            .monospaced()
                    }
                }
            }
        }
    }
}

private extension StatementKind {
    var label: String {
        switch self {
        case .income: "Income Statement"
        case .balance: "Balance Sheet"
        case .cashFlow: "Cash Flow"
        }
    }
}

private extension StatementCadence {
    var label: String {
        switch self {
        case .quarterly: "Quarterly"
        case .annual: "Annual"
        }
    }
}
