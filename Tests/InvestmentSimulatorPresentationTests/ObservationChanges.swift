import Observation
import Synchronization

/// Whether `change` changes anything `read` observes, which is what has
/// SwiftUI draw a view again whose body did `read` (PIN-522).
@MainActor
func changesObserved(by read: () -> Void, when change: () -> Void) -> Bool {
    let changed = ChangeFlag()
    withObservationTracking(read, onChange: { changed.raise() })
    change()
    return changed.isRaised
}

/// Set from `withObservationTracking`'s `onChange`, which must be `Sendable`.
private final class ChangeFlag: Sendable {
    private let raised = Mutex(false)

    var isRaised: Bool {
        raised.withLock { $0 }
    }

    func raise() {
        raised.withLock { $0 = true }
    }
}
