import SwiftUI

/// The Experiment section's detail: the starting cash balance, shown large.
struct ExperimentDetailView: View {
    let cashBalance: Decimal

    var body: some View {
        VStack(spacing: 8) {
            Text("Cash Balance")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(cashBalance, format: .currency(code: "USD"))
                .font(.system(size: 56, weight: .semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
