import Charts
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
                ResearchTickerView(
                    tab: tab,
                    onRefresh: { model.refresh(tab.ticker) },
                    onShowRange: { model.showRange($0, for: tab.ticker) },
                )
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
    let onShowRange: @MainActor (PriceRange) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(tab.ticker.symbol)
                    .font(.largeTitle.bold())
                quote
                ResearchChartSection(tab: tab, onShowRange: onShowRange)
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

/// A ticker's price history: a range picker over a line of closes, with
/// its own loading, empty and error states.
struct ResearchChartSection: View {
    let tab: ResearchTabModel
    let onShowRange: @MainActor (PriceRange) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Range", selection: Binding(get: { tab.chartRange }, set: { onShowRange($0) })) {
                ForEach(PriceRange.allCases, id: \.self) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            chart
                .frame(height: 240)
        }
    }

    @ViewBuilder private var chart: some View {
        switch tab.chartState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(points):
            Chart(points, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("Close", point.close))
            }
            .chartYScale(domain: .automatic(includesZero: false))
        case .empty:
            Text("No price history for \(tab.ticker.symbol).")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(error):
            Text(error.localizedDescription)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private extension PriceRange {
    var label: String {
        switch self {
        case .oneMonth: "1M"
        case .sixMonths: "6M"
        case .oneYear: "1Y"
        case .fiveYears: "5Y"
        }
    }
}
