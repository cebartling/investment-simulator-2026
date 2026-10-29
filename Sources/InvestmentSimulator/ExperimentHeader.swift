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

    /// One row when the window is wide enough, else two or three, so no
    /// value is ever cut short.
    private func tiles(at date: Date) -> some View {
        let total = totalValueTile
        let gain = gainTile
        let cash = HeaderTile(title: "Cash", value: currency(model.cashBalance))
        let available = availableTile(at: date)
        let invested = HeaderTile(title: "Invested", value: currency(model.experiment.investedCost.amount))
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                total
                gain
                cash
                available
                invested
            }
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow { total; gain; cash }
                GridRow { available; invested }
            }
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow { total; gain }
                GridRow { cash; available }
                GridRow { invested }
            }
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
        .frame(minWidth: 120, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
