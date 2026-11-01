import Observation

/// The open experiment windows, so Research can start a purchase in one
/// (ADR-0020). It only routes: each window's model keeps its own state.
@Observable
public final class OpenExperiments {
    public struct Entry: Identifiable {
        public let model: MainWindowModel
        public let title: String

        public var id: ObjectIdentifier {
            ObjectIdentifier(model)
        }
    }

    /// In the order opened.
    public private(set) var entries: [Entry] = []

    public init() {}

    /// Adds a window, or changes the title of one already listed.
    public func register(_ model: MainWindowModel, title: String) {
        let entry = Entry(model: model, title: title)
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    public func remove(_ model: MainWindowModel) {
        entries.removeAll { $0.model === model }
    }
}
