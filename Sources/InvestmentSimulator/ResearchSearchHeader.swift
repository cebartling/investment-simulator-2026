import InvestmentSimulatorPresentation
import SwiftUI

/// The Research view's header: a field for a ticker or company name, and the
/// messages about what was typed. It stays at the top while the ticker's
/// research scrolls (PIN-482).
struct ResearchSearchHeader: View {
    @Bindable var model: ResearchWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Ticker or company", text: $model.symbolText, prompt: Text("Ticker or company…"))
                .onSubmit { model.open() }
                .task(id: model.symbolText) { await model.search() }
                .frame(maxWidth: 360)
            if let message = model.symbolMessage ?? model.openError?.localizedDescription {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let message = model.searchMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
