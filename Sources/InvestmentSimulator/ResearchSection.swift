import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// A titled section of a ticker's research, with its own loading, empty and
/// error states.
struct ResearchSection<Value: Equatable, Content: View>: View {
    let title: String
    let state: ResearchSectionState<Value>
    let ticker: Ticker
    /// What the section shows, for its empty text, if not its title in
    /// lowercase.
    var subject: String?
    let onRetry: () -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ResearchSectionContent(
                state: state,
                ticker: ticker,
                subject: subject ?? title.lowercased(),
                onRetry: onRetry,
                content: content,
            )
        }
    }
}

/// A section's loaded content, or its loading, empty or error state.
struct ResearchSectionContent<Value: Equatable, Content: View>: View {
    let state: ResearchSectionState<Value>
    let ticker: Ticker
    let subject: String
    let onRetry: () -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.small)
        case let .loaded(value):
            content(value)
        case let .empty(reason):
            Text(reason.message(subject: subject, ticker: ticker))
                .foregroundStyle(.secondary)
        case let .failed(error):
            Text(error.localizedDescription)
                .foregroundStyle(.red)
            Button("Retry", action: onRetry)
        }
    }
}
