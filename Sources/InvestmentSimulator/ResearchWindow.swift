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
            ResearchSidebar(model: model)
        } detail: {
            if let tab = model.selectedTab {
                ResearchTickerView(
                    tab: tab,
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
        .frame(minWidth: 900, minHeight: 480)
    }
}

/// One ticker's research. Its sections stack below the quote.
struct ResearchTickerView: View {
    let tab: ResearchTabModel
    let onRefresh: () -> Void
    let onShowRange: @MainActor (PriceRange) -> Void
    let onRetry: @MainActor (ResearchTabModel.Section) -> Void
    let onShowStatements: @MainActor (StatementSelection) -> Void
    let onHideStatements: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(tab.ticker.symbol)
                    .font(.largeTitle.bold())
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
                    content: ResearchFilingsView.init,
                )
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
                // A line through one point draws nothing.
                if points.count == 1 {
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

/// The company's own releases, each opening in the browser.
struct ResearchPressReleasesView: View {
    let releases: [PressRelease]

    var body: some View {
        let dates = PriceDateFormatter()
        VStack(alignment: .leading, spacing: 8) {
            // By position: two releases can match in every field.
            ForEach(Array(releases.enumerated()), id: \.offset) { _, release in
                VStack(alignment: .leading, spacing: 2) {
                    // Link's title initializer centers a title that wraps,
                    // whatever the environment's alignment.
                    Link(destination: release.url) {
                        Text(release.title)
                            .multilineTextAlignment(.leading)
                    }
                    Text(dates.marketDay(of: release.publishedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let summary = release.summary {
                        Text(summary)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// Recent filings, each opening on its Equibles page in the browser.
struct ResearchFilingsView: View {
    let filings: [Filing]

    var body: some View {
        let dates = PriceDateFormatter()
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
            GridRow {
                Text("Form")
                Text("Filed")
                Text("Reporting For")
            }
            .foregroundStyle(.secondary)
            // By position: two filings can match in every field.
            ForEach(Array(filings.enumerated()), id: \.offset) { _, filing in
                GridRow {
                    Link(filing.form, destination: filing.url)
                    Text(dates.day(ofSession: filing.filedDate))
                    Text(filing.reportingForDate.map(dates.day(ofSession:)) ?? ResearchFigureFormatter.missing)
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
