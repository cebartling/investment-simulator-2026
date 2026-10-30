import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// The app-wide Research window (ADR-0019): open tickers in the sidebar,
/// in the order opened, and the selected ticker's research beside them.
struct ResearchWindow: View {
    @Bindable var model: ResearchWindowModel

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Ticker", text: $model.symbolText, prompt: Text("Open ticker…"))
                    .onSubmit { model.open() }
                if let message = model.symbolMessage ?? model.openError?.localizedDescription {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
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
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            if let tab = model.selectedTab {
                ResearchTickerView(tab: tab, onRefresh: { model.refresh(tab.ticker) })
            } else {
                // A sidebar list can be deselected with tickers still open.
                ContentUnavailableView(
                    model.tabs.isEmpty ? "No Ticker Open" : "No Ticker Selected",
                    systemImage: "magnifyingglass",
                    description: Text("Type a ticker symbol, such as VTI, to research it."),
                )
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

/// One ticker's research. Its sections stack below the quote.
struct ResearchTickerView: View {
    let tab: ResearchTabModel
    let onRefresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(tab.ticker.symbol)
                    .font(.largeTitle.bold())
                quote
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    @ViewBuilder private var quote: some View {
        switch tab.quoteState {
        case .loading:
            ProgressView()
                .controlSize(.small)
        case let .quoted(quote):
            VStack(alignment: .leading, spacing: 4) {
                Text(quote.price, format: .currency(code: "USD").precision(.fractionLength(2 ... 4)))
                    .font(.title2)
                    .monospaced()
                Text(PriceDateFormatter().label(for: quote))
                    .foregroundStyle(.secondary)
            }
        case let .failed(error):
            VStack(alignment: .leading, spacing: 8) {
                Text(error.localizedDescription)
                    .foregroundStyle(.red)
                HStack {
                    if tab.needsAPIKey {
                        SettingsLink {
                            Text("Open Settings…")
                        }
                    }
                    Button("Refresh", action: onRefresh)
                }
            }
        }
    }
}
