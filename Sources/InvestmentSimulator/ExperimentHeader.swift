import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import SwiftUI

/// The top of the Experiment section: what the experiment is called, when
/// and with what it started, and a row of tiles for its value and cash
/// (PIN-408).
struct ExperimentHeader: View {
    let model: MainWindowModel
    let title: String
    let onEditDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBlock
            // Redrawn every minute, so Available rises as buy orders expire.
            TimelineView(.everyMinute) { context in
                tiles(at: context.date)
            }
        }
        .padding(.horizontal, 20)
    }

    /// Edit Details… sits beside the title when it fits, else below it, so
    /// the subtitle is never cut short.
    private var titleBlock: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                titleText
                Spacer()
                editDetailsButton
            }
            VStack(alignment: .leading, spacing: 8) {
                titleText
                editDetailsButton
            }
        }
    }

    private var titleText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title2.bold())
                .lineLimit(1)
                .help(title)
            Text(subtitle)
                .foregroundStyle(.secondary)
            if let notes = model.experiment.notes {
                Text(notes)
                    .lineLimit(2)
                    .help(notes)
            }
        }
    }

    private var editDetailsButton: some View {
        Button("Edit Details…", action: onEditDetails)
            .help("Change the experiment's name and notes")
    }

    private var subtitle: String {
        let startingCash = model.experiment.startingCash.amount.formatted(.currency(code: "USD"))
        guard let createdAt = model.experiment.createdAt else {
            return "Started with \(startingCash)"
        }
        return "Started \(createdAt.formatted(date: .abbreviated, time: .omitted)) with \(startingCash)"
    }

    private var valuation: HoldingsPricesModel.Valuation {
        model.holdingsPrices.valuation(of: model.experiment)
    }

    /// One row when the window is wide enough, else more, so no value is
    /// ever cut short. Every tile is as tall as the tallest (PIN-509).
    private func tiles(at date: Date) -> some View {
        let total = totalValueTile
        let gain = gainTile
        let cash = HeaderTile(title: "Cash", value: currency(model.cashBalance))
        let available = availableTile(at: date)
        let invested = HeaderTile(title: "Invested", value: currency(model.experiment.investedCost.amount))
        return EqualHeightTileLayout(spacing: 12) {
            total
            gain
            cash
            available
            invested
        }
    }

    private var totalValueTile: HeaderTile {
        guard case let .valued(totalValue, _, _) = valuation else {
            return HeaderTile(title: "Total Value", value: Self.unknown)
        }
        return HeaderTile(title: "Total Value", value: currency(totalValue.amount))
    }

    private var gainTile: HeaderTile {
        guard case let .valued(_, gain, _) = valuation else {
            return HeaderTile(title: "Gain/Loss", value: Self.unknown)
        }
        let amount = gain.amount.amount.formatted(.currency(code: "USD").sign(strategy: .always(showZero: false)))
        let percent = gain.percent.map {
            ($0 / 100).formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)))
        }
        let color: Color? = gain.amount > .zero ? .green : gain.amount < .zero ? .red : nil
        return HeaderTile(title: "Gain/Loss", value: amount, caption: percent ?? Self.unknown, color: color)
    }

    private func availableTile(at date: Date) -> HeaderTile {
        let reserved = model.reservedCash(at: date)
        return HeaderTile(
            title: "Available",
            value: currency(model.availableCash(at: date)),
            caption: reserved > 0 ? "\(currency(reserved)) reserved" : nil,
        )
    }

    private static let unknown = "—"

    private func currency(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "USD"))
    }
}

/// One figure in the header: a title over its value, with an optional
/// caption. The value is never truncated.
private struct HeaderTile: View {
    let title: String
    let value: String
    var caption: String?
    var color: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color ?? .primary)
                .fixedSize()
            if let caption {
                Text(caption)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(color ?? .secondary)
                    .fixedSize()
            }
        }
        .padding(10)
        .frame(minWidth: 120, maxHeight: .infinity, alignment: .topLeading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Lays tiles out left to right, wrapping to a new row when the next tile
/// won't fit, and gives every tile the height of the tallest one, in every
/// row. Tiles keep their own widths.
private struct EqualHeightTileLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = Self.rows(of: sizes, maxWidth: proposal.width ?? .infinity, spacing: spacing)
        let tileHeight = sizes.map(\.height).max() ?? 0
        var width: CGFloat = 0
        for row in rows {
            let tilesWidth: CGFloat = row.reduce(0) { $0 + sizes[$1].width }
            let rowWidth: CGFloat = tilesWidth + spacing * CGFloat(row.count - 1)
            width = max(width, rowWidth)
        }
        let height = tileHeight * CGFloat(rows.count) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let tileHeight = sizes.map(\.height).max() ?? 0
        let rows = Self.rows(of: sizes, maxWidth: bounds.width, spacing: spacing)
        var originY = bounds.minY
        for row in rows {
            var originX = bounds.minX
            for index in row {
                subviews[index].place(
                    at: CGPoint(x: originX, y: originY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: sizes[index].width, height: tileHeight),
                )
                originX += sizes[index].width + spacing
            }
            originY += tileHeight + spacing
        }
    }

    /// Indices of the tiles in each row. A tile wider than the space still
    /// gets a row of its own.
    private static func rows(of sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var rowWidth: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            if let last = rows.indices.last, rowWidth + spacing + size.width <= maxWidth {
                rows[last].append(index)
                rowWidth += spacing + size.width
            } else {
                rows.append([index])
                rowWidth = size.width
            }
        }
        return rows
    }
}
