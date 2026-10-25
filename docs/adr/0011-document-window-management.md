# ADR-0011: Document Window Management, with One AppKit Close

**Status:** Accepted
**Date:** 2026-10-24
**Deciders:** Christopher Bartling

Supersedes ADR-0010.

## Context

ADR-0010 kept `WindowGroup` until the first scenario document existed, gave each window its own composition root, and left window frames to SwiftUI with no `NSWindow` access. It asked for two things to be rechecked once `DocumentGroup` landed. If they didn't hold, it was to be superseded.

PIN-398 made the app document-based. An experiment (ADR-0005's *scenario*) is a `.invsim` document, and File › New creates an untitled one and immediately shows a New Experiment sheet. Testing against the bundled app on 2026-10-24 found the following.

**Frames are no longer remembered.** A document window resized to 1100×700 reopened at the default 900×452, cascaded. New documents also open at the default size. No `DocumentGroup` window writes an `NSWindow Frame` key to `UserDefaults`. Under `WindowGroup`, frames were saved under a key built from the root view's type name. This undoes the behavior PIN-397 was closed on.

**SwiftUI can't close a `DocumentGroup` window.** Cancelling the New Experiment sheet should close the new document. But:

- `@Environment(\.dismiss)` doesn't close the document window.
- `@Environment(\.dismissWindow)`, called with no arguments, doesn't close it either, whether the sheet is attached or not.
- AppKit won't close a window while a sheet is attached. SwiftUI's sheet is still attached when the sheet's `onDismiss` runs, so a `performClose` there does nothing.

## Decision

- **The app uses `DocumentGroup`** (ADR-0005). ADR-0010's interim `WindowGroup` is gone.
- **The composition root is scoped to a document window.** `MainWindow`, the root view of each document, creates its own presentation model from its document, so windows share no UI state. App-wide services, once they exist, are built once at the `App` level and passed into each window's root view through its initializer (ADR-0004). They never go in `@Environment`.
- **Windows are configured only through SwiftUI scene and view modifiers,** such as `.defaultSize`, `.windowResizability`, `.defaultWindowPlacement`, `.restorationBehavior` and `frame` constraints. No autosave names and no custom frame storage.
- **One exception to "no `NSWindow` access": closing a cancelled new document.** The app target's `WindowCloser`, an `NSViewRepresentable`, ends any attached sheet (`endSheet`) and then calls `performClose(nil)` once, so the document's own close handling still runs. `MainWindowModel.cancelNewExperiment()` decides when to close, and is unit tested. Any further `NSWindow` use needs its own ADR.
- **Window frames are not remembered for now.** This is accepted as a known regression from PIN-397, and restoring it is PIN-399. That ticket starts by checking what SwiftUI offers for `DocumentGroup`. If the fix needs AppKit (for example autosave names), it supersedes this ADR.
- **Check native behavior first.** A new window-state requirement starts with an experiment against the bundled app (`just open`), reading `UserDefaults` and real window bounds, before any custom code is planned.

## Options Considered

### Option A: `WindowCloser` ends the sheet, then calls `performClose` once (chosen)

**Pros:**
- Cancel does what it says: no stray $0 document is left behind.
- `performClose` goes through the normal document close path, so it would still prompt if the document had unsaved changes. Requesting the close only once means a refused close isn't retried on every redraw.
- The window logic sits in one small type, and the decision to close is tested in Presentation.

**Cons:**
- It is `NSWindow` access, which ADR-0010 ruled out, hence this ADR.
- It depends on AppKit details SwiftUI could change, such as the sheet still being attached during `onDismiss`. It can only be verified by hand, since the app target has no tests (ADR-0007).

### Option B: Cancel only hides the sheet and leaves a $0.00 document open

**Pros:**
- Pure SwiftUI.
- An unedited document closes with ⌘W and no save prompt.

**Cons:**
- "Cancel" leaves an experiment open, which isn't what the word means.

### Option C: Close the key window (`NSApp.keyWindow?.performClose`)

**Pros:**
- One line, with no representable view.

**Cons:**
- While the sheet is up, the key window is the sheet rather than the document, so this can close the wrong window.

### Option D: Restore window frames in PIN-398

**Pros:**
- No regression from PIN-397.

**Cons:**
- The approach is unknown and may need AppKit autosave, which SwiftUI overrode for `WindowGroup`. That would grow the ticket that introduces documents.

## Consequences

- **Easier:** Cancel behaves as users expect; the close decision is covered by Presentation tests; one model per document carries forward.
- **Harder:**
  - One AppKit dependency in the app target, checked only by hand: ⌘N, then Escape, should leave no new window.
  - Users lose remembered window frames until the follow-up lands.
- **Revisit:**
  - If a later SwiftUI release lets `dismissWindow` or `dismiss` close a `DocumentGroup` window, remove `WindowCloser` and supersede this ADR.
  - Window frame persistence for documents, in the follow-up ticket.
