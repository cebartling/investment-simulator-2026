import InvestmentSimulatorPresentation
import SwiftUI

struct ContentView: View {
    @Bindable var model: MainWindowModel

    var body: some View {
        NavigationSplitView {
            List(model.sections, selection: $model.selection) { section in
                Label(section.title, systemImage: section.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            if let section = model.selection {
                ContentUnavailableView(section.title, systemImage: section.systemImage)
            } else {
                ContentUnavailableView("No Selection", systemImage: "sidebar.left")
            }
        }
        .frame(minWidth: 640, minHeight: 400)
    }
}

private extension NavigationSection {
    var systemImage: String {
        switch self {
        case .scenario: "slider.horizontal.3"
        case .simulation: "play.circle"
        case .results: "chart.line.uptrend.xyaxis"
        }
    }
}
