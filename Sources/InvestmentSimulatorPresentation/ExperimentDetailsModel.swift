import Foundation
import Observation

/// Drives the Edit Details sheet: the experiment's name and notes.
@Observable
public final class ExperimentDetailsModel {
    public var name: String
    public var notes: String

    public init(name: String?, notes: String?) {
        self.name = name ?? ""
        self.notes = notes ?? ""
    }

    /// The name to save: trimmed, or nil when blank.
    public var savedName: String? {
        Self.saved(name)
    }

    /// The notes to save: trimmed at both ends, or nil when blank.
    public var savedNotes: String? {
        Self.saved(notes)
    }

    private static func saved(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
