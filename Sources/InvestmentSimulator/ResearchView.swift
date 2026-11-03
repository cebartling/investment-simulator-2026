import Charts
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// Research in the library window's detail (ADR-0019, ADR-0021): a search
/// header, then open tickers beside the selected ticker's research, or the
/// search matches while there are any.
struct ResearchView: View {
    @Bindable var model: ResearchWindowModel
    let library: LibraryWindowModel

    var body: some View {
        // Not a second NavigationSplitView: the library window has the one.
        VStack(spacing: 0) {
            ResearchSearchHeader(model: model)
            Divider()
            HStack(spacing: 0) { // not an HSplitView: no draggable divider
                if !model.tabs.isEmpty {
                    ResearchSidebar(model: model)
                        .frame(width: 220)
                }
                detail
            }
            .frame(maxHeight: .infinity) // else the stack centres in the window
        }
        // The saved tickers load when Research is first shown, not at launch.
        .task { model.restore() }
    }

    @ViewBuilder private var detail: some View {
        if !model.searchResults.isEmpty {
            ResearchSearchResults(model: model)
        } else if let tab = model.selectedTab {
            ResearchTickerView(
                tab: tab,
                library: library,
                onRefresh: { model.refresh(tab.ticker) },
                onShowRange: { model.showRange($0, for: tab.ticker) },
                onRetry: { model.retry($0, for: tab.ticker) },
                onShowStatements: { model.showStatements($0, for: tab.ticker) },
                onHideStatements: { model.hideStatements(for: tab.ticker) },
            )
        } else {
            // A sidebar list can be deselected with tickers still open.
            ContentUnavailableView(
                model.tabs.isEmpty ? "No Ticker Open" : "No Ticker Selected",
                systemImage: "magnifyingglass",
                description: Text("Type a ticker symbol or company name to research it."),
            )
        }
    }
}

/// One ticker's research. Its sections stack below the quote.
struct ResearchTickerView: View {
    let tab: ResearchTabModel
    let library: LibraryWindowModel
    let onRefresh: () -> Void
    let onShowRange: @MainActor (PriceRange) -> Void
    let onRetry: @MainActor (ResearchTabModel.Section) -> Void
    let onShowStatements: @MainActor (StatementSelection) -> Void
    let onHideStatements: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(tab.ticker.symbol)
                        .font(.largeTitle.bold())
                    Spacer()
                    buyMenu
                }
                quote
                ResearchChartSection(tab: tab, onShowRange: onShowRange)
                ResearchSection(
                    title: "Profile",
                    state: tab.profileState,
                    ticker: tab.ticker,
                    onRetry: { onRetry(.profile) },
                    content: {
                        ResearchProfileView(
                            profile: $0,
                            exchangeState: tab.exchangeState,
                            exchangeMessage: tab.exchangeMessage,
                            onRetryExchange: { onRetry(.exchange) },
                        )
                    },
                )
                ResearchSection(
                    title: "Valuation Multiples",
                    state: tab.multiplesState,
                    ticker: tab.ticker,
                    onRetry: { onRetry(.multiples) },
                    content: ResearchMultiplesView.init,
                )
                ResearchStatementsSection(tab: tab, onShow: onShowStatements, onHide: onHideStatements)
                ResearchSection(
                    title: "Dividends",
                    state: tab.dividendsState,
                    ticker: tab.ticker,
                    onRetry: { onRetry(.dividends) },
                    content: { ResearchDividendsView(history: $0, yield: tab.dividendYield) },
                )
                ResearchSection(
                    title: "Press Releases",
                    state: tab.pressReleasesState,
                    ticker: tab.ticker,
                    onRetry: { onRetry(.pressReleases) },
                    content: ResearchPressReleasesView.init,
                )
                ResearchSection(
                    title: "SEC Filings",
                    state: tab.filingsState,
                    ticker: tab.ticker,
                    // Only these forms are kept: a fund or foreign issuer
                    // files others, so "no SEC filings" would be untrue.
                    subject: "10-K, 10-Q or 8-K filings",
                    onRetry: { onRetry(.filings) },
                    content: { ResearchFilingsView(filings: $0, link: tab.link(for:)) },
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    /// One entry per experiment in the library (ADR-0021).
    private var buyMenu: some View {
        Menu("Buy in Experiment…") {
            ForEach(library.library.summaries) { summary in
                Menu(library.library.title(for: summary)) {
                    Button("Market Buy…") {
                        Task { await library.beginPurchase(of: tab.ticker, in: summary.id) }
                    }
                    Button("Buy Limit…") {
                        Task { await library.beginBuyLimitOrder(of: tab.ticker, in: summary.id) }
                    }
                }
            }
        }
        .fixedSize()
        .disabled(library.library.summaries.isEmpty)
        .help("Open Market Buy or Buy Limit for this ticker in an experiment")
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
    /// The one zone that places the points and lays out the axis.
    @Environment(\.timeZone) private var timeZone

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
            let plotted = ChartPoint.plot(points, in: timeZone)
            Chart(plotted, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("Close", point.close))
                // A line through one point draws nothing.
                if plotted.count == 1 {
                    PointMark(x: .value("Date", point.date), y: .value("Close", point.close))
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
        case .empty:
            Text("No price history for \(tab.ticker.symbol).")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(error):
            VStack(spacing: 8) {
                Text(error.localizedDescription)
                    .foregroundStyle(.red)
                // A failed range isn't kept, so showing it again retries it.
                Button("Retry") { onShowRange(tab.chartRange) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Who the company is and what it's worth.
struct ResearchProfileView: View {
    let profile: CompanyProfile
    let exchangeState: ResearchSectionState<String>
    let exchangeMessage: String?
    let onRetryExchange: @MainActor () -> Void

    var body: some View {
        let formatter = ResearchFigureFormatter()
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.name)
            if let classification = formatter.classification(of: profile) {
                Text(classification)
                    .foregroundStyle(.secondary)
            }
            if case let .loaded(exchange) = exchangeState {
                Text(exchange)
                    .foregroundStyle(.secondary)
            }
            Text("Market cap \(formatter.marketCap(profile.marketCap))")
            if let exchangeMessage {
                Text(exchangeMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Saving the email in Settings doesn't reach an open ticker.
                Button("Retry", action: onRetryExchange)
            }
        }
    }
}

/// The company's ratios beside its industry peers.
struct ResearchMultiplesView: View {
    let multiples: ValuationMultiples

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 20, verticalSpacing: 4) {
            GridRow {
                Text("Ratio")
                    .gridColumnAlignment(.leading)
                Text("Value")
                Text("Peer P25")
                Text("Peer Median")
                Text("Peer P75")
            }
            .foregroundStyle(.secondary)
            row("P/E", multiples.peRatio)
            row("EV/Revenue", multiples.evToRevenue)
            row("EV/EBIT", multiples.evToEbit)
        }
    }

    private func row(_ name: String, _ ratio: ValuationRatio) -> some View {
        let formatter = ResearchFigureFormatter()
        return GridRow {
            Text(name)
            Group {
                Text(formatter.ratio(ratio.value))
                Text(formatter.ratio(ratio.peerP25))
                Text(formatter.ratio(ratio.peerMedian))
                Text(formatter.ratio(ratio.peerP75))
            }
            .monospaced()
        }
    }
}

/// The trailing yield, then dividends declared for later and those paid.
struct ResearchDividendsView: View {
    let history: DividendHistory
    let yield: Decimal?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trailing 12-month yield \(ResearchFigureFormatter().yield(yield))")
            if !history.declared.isEmpty {
                rows("Declared", history.declared)
            }
            if !history.paid.isEmpty {
                rows("Paid", history.paid)
            }
        }
    }

    private func rows(_ title: String, _ dividends: [Dividend]) -> some View {
        let dates = PriceDateFormatter()
        let figures = ResearchFigureFormatter()
        return Grid(alignment: .trailing, horizontalSpacing: 20, verticalSpacing: 4) {
            GridRow {
                Text("\(title) Ex-Date")
                    .gridColumnAlignment(.leading)
                Text("Amount")
            }
            .foregroundStyle(.secondary)
            // By position: two dividends can match in every field.
            ForEach(Array(dividends.enumerated()), id: \.offset) { _, dividend in
                GridRow {
                    Text(dates.day(ofSession: dividend.exDate))
                    Text(figures.dividendAmount(dividend.amountPerShare, currency: dividend.currency))
                        .monospaced()
                }
            }
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
