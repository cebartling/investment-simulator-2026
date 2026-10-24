# ADR-0011: Close a Cancelled New Document Through AppKit

**Status:** Accepted
**Date:** 2026-10-24
**Deciders:** Christopher Bartling

## Context

PIN-398 made the app document-based (ADR-0005). File › New creates an untitled experiment document and immediately shows a New Experiment sheet for its starting cash balance. Cancelling that sheet should close the new document, because the user has decided not to create an experiment.

ADR-0010 says windows are configured only through SwiftUI scene and view modifiers, with no `NSWindow` access. SwiftUI offers no way to close a `DocumentGroup` window from inside it. Testing against the bundled app on 2026-10-24 showed that:

- `@Environment(\.dismiss)` doesn't close the document window.
- `@Environment(\.dismissWindow)`, called with no arguments, doesn't close it either, whether the sheet is attached or not.
- AppKit won't close a window while a sheet is attached. SwiftUI's sheet is still attached when the sheet's `onDismiss` runs, so a `performClose` there does nothing.

## Decision

- **One narrow exception to ADR-0010's "no `NSWindow` access":** the app target's `WindowCloser`, an `NSViewRepresentable`, closes its hosting window. It ends any attached sheet (`endSheet`), then calls `performClose(nil)`, so the document's own close handling still runs.
- **Presentation decides when; the view only carries it out.** `MainWindowModel.cancelNewExperiment()` hides the sheet and sets `shouldCloseWindow`, which is unit tested. `ContentView` passes that flag to `WindowCloser`.
- **The exception covers closing a window only.** Frame, placement and every other window configuration stay with SwiftUI as ADR-0010 requires. Any further `NSWindow` use needs its own ADR.

## Options Considered

### Option A: `WindowCloser` ends the sheet, then calls `performClose` (chosen)

**Pros:**
- Cancel does what it says: no stray $0 document is left behind.
- `performClose` goes through the normal document close path, so it would still prompt if the document had unsaved changes.
- The window logic sits in one small type, and the decision to close is tested in Presentation.

**Cons:**
- It breaks ADR-0010's "no `NSWindow` access" rule, so it needs this ADR.
- It depends on AppKit details SwiftUI could change, such as the sheet still being attached during `onDismiss`. It can only be verified by hand, since the app target has no tests (ADR-0007).

### Option B: Cancel only hides the sheet and leaves a $0.00 document open

**Pros:**
- Pure SwiftUI, within ADR-0010.
- An unedited document closes with ⌘W and no save prompt.

**Cons:**
- "Cancel" leaves an experiment open, which isn't what the word means.

### Option C: Close the key window (`NSApp.keyWindow?.performClose`)

**Pros:**
- One line, with no representable view.

**Cons:**
- While the sheet is up, the key window is the sheet rather than the document, so this can close the wrong window.
- It still touches AppKit, so it needs the same exception with less precision.

## Consequences

- **Easier:** Cancel behaves as users expect; the close decision is covered by Presentation tests.
- **Harder:** one AppKit dependency in the app target, checked only by hand: ⌘N, then Escape, should leave no new window.
- **Revisit:** if a later SwiftUI release lets `dismissWindow` or `dismiss` close a `DocumentGroup` window, remove `WindowCloser` and supersede this ADR.
