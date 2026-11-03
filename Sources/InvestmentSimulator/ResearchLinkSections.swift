import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

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

/// Recent filings, each opening in the browser on the page `link` gives:
/// sec.gov once EDGAR has listed the ticker, otherwise Equibles.
struct ResearchFilingsView: View {
    let filings: [Filing]
    let link: (Filing) -> URL

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
                    Link(filing.form, destination: link(filing))
                    Text(dates.day(ofSession: filing.filedDate))
                    Text(filing.reportingForDate.map(dates.day(ofSession:)) ?? ResearchFigureFormatter.missing)
                }
            }
        }
    }
}
