import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// The Research window's sidebar: the open tickers, which the matches for the
/// header's search text replace while there are any.
struct ResearchSidebar: View {
    @Bindable var model: ResearchWindowModel

    var body: some View {
        Group {
            if model.searchResults.isEmpty {
                openTickers
            } else {
                searchResults
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }

    private var openTickers: some View {
        List(model.tabs, selection: $model.selection) { tab in
            HStack {
                Text(tab.ticker.symbol)
                Spacer()
                Button("Close \(tab.ticker.symbol)", systemImage: "xmark") {
                    model.close(tab.ticker)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Close \(tab.ticker.symbol)")
            }
        }
        .contextMenu(forSelectionType: Ticker.self) { tickers in
            if let ticker = tickers.first {
                Button("Close") { model.close(ticker) }
            }
        }
        .onDeleteCommand {
            if let ticker = model.selection {
                model.close(ticker)
            }
        }
    }

    /// Clicking a match opens it. Return in the field opens the top match
    /// only when the text matches no symbol.
    private var searchResults: some View {
        List(model.searchResults, id: \.ticker) { security in
            Button {
                model.open(security.ticker)
            } label: {
                ResearchSearchResultRow(security: security)
            }
            .buttonStyle(.plain)
        }
    }
}

/// One match for the text in the Research sidebar's field.
struct ResearchSearchResultRow: View {
    let security: ListedSecurity

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(security.ticker.symbol)
                    .bold()
                Spacer()
                if let exchange = security.exchange {
                    Text(exchange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(security.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        // The whole row is the click target, not only its text.
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}
