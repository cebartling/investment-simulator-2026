/// One pane of a ticker's research, shown below its header. A new analysis
/// adds a case here and a branch in the view's pane switch.
public enum ResearchPane: CaseIterable, Hashable, Sendable {
    case overview
    case valuation
    case financials
    case dividends
    case news
    case filings

    public var label: String {
        switch self {
        case .overview: "Overview"
        case .valuation: "Valuation"
        case .financials: "Financials"
        case .dividends: "Dividends"
        case .news: "News"
        case .filings: "Filings"
        }
    }
}
