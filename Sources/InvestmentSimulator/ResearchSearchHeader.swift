import InvestmentSimulatorPresentation
import SwiftUI

/// The Research view's header: a field for a ticker or company name, with a
/// message about what was typed beside it. It stays at the top while the
/// ticker's research scrolls (PIN-482). The field sets the header's height, so
/// the panes below don't move as messages come and go.
struct ResearchSearchHeader: View {
    @Bindable var model: ResearchWindowModel

    var body: some View {
        HStack(spacing: 12) {
            TextField("Ticker or company", text: $model.symbolText, prompt: Text("Ticker or company…"))
                .onSubmit { model.open() }
                .task(id: model.symbolText) { await model.search() }
                .frame(maxWidth: 360)
            message
                .font(.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.horizontal, 12)
        .background(.bar)
    }

    /// An error wins over the search message.
    @ViewBuilder private var message: some View {
        if let error = model.symbolMessage ?? model.openError?.localizedDescription {
            Text(error)
                .foregroundStyle(.red)
        } else if let search = model.searchMessage {
            Text(search)
                .foregroundStyle(.secondary)
        }
    }
}
