# ADR-0020: Buying from Research Through a Registry of Open Experiments

**Status:** Superseded by ADR-0021
**Date:** 2026-10-31
**Deciders:** Christopher Bartling

Amends ADR-0011. Superseded by ADR-0021.

## Context

PIN-421 adds "Buy in Experiment…" to a Research ticker: it opens Market Buy or Buy Limit in an experiment window with the ticker filled in. Research is one app-wide window (ADR-0019). Each experiment is a document window that is its own composition root, and ADR-0011 says windows share no UI state, so Research has no way to reach one.

Testing against the bundled app on 2026-10-31 found the following.

- **`FocusedValue` can't find the target.** With Research key and the app active, `@FocusedValue` in Research read nil for a `focusedSceneValue` set by each document window. Research is the focused scene whenever its button is clicked.
- **`openDocument(at:)` raises an open document,** but only one with a file. An untitled document has no URL.
- **`makeKeyAndOrderFront` raises any document window.** It brought forward a background window, restored a minimized one, and selected a background tab after Merge All Windows.
- **`onAppear` and `onDisappear` on `MainWindow` track a window's life.** `onDisappear` ran on closing a window and on cancelling a new document, and didn't run on minimizing it, merging it into tabs or switching tabs.
- **A sheet presents on a window that isn't key,** including one whose sidebar selection was nil, once the selection is set back to Experiment.

## Decision

- **`OpenExperiments` lists the open experiment windows.** It's an `@Observable` class in Presentation, built once as `@State` on `InvestmentSimulatorApp` and passed through initializers, never `@Environment`. Each entry pairs a window's `MainWindowModel` with its title.
- **Each `MainWindow` adds and removes itself:** on appear, on disappear, and whenever its title changes, so the list follows Save As and renames.
- **The list only routes.** Research reads the titles and whether a window can take a hand-off, and calls one of two methods on the chosen model: `beginPurchase(of:)` or `beginBuyLimitOrder(of:)`. The window's model keeps owning its experiment and sheets, and writes to its own document as before.
- **Research shows a menu.** "Buy in Experiment…" lists each open experiment, each with Market Buy… and Buy Limit…. It's disabled when none is open.
- **A window showing any sheet can't be targeted,** so a hand-off never replaces what the user is typing. Its Market Buy… and Buy Limit… items are disabled, and the two methods do nothing if called anyway.
- **A second exception to "no `NSWindow` access": `WindowRaiser`.** A sheet on a background window would go unseen, and `openDocument(at:)` can't reach an untitled document. This `NSViewRepresentable` in the app target calls `makeKeyAndOrderFront(nil)` when the model's `raiseCount` changes, and `MainWindowModel` decides when, which is unit tested.

## Options Considered

### Option A: A menu backed by a registry (chosen)

**Pros:**
- The sheets open filled in, and the user picks the experiment, however many are open.
- Works for untitled documents.
- The routing is in Presentation, so it's unit tested.

**Cons:**
- One app-wide object that refers to every window's model, narrowing ADR-0011's "windows share no UI state".
- A second `NSWindow` exception.

### Option B: The most recently active experiment

**Pros:**
- One click fewer, with no menu.

**Cons:**
- It needs the same registry, and can silently buy in the wrong experiment.

### Option C: Copy the ticker only

**Pros:**
- No state crosses windows, and there's almost nothing to build.

**Cons:**
- The sheets don't open filled in, which is what PIN-421 asks for.

### Option D: `FocusedValue`, or `openDocument(at:)` alone

**Pros:**
- Pure SwiftUI.

**Cons:**
- `FocusedValue` reads nil from Research, as found above.
- `openDocument(at:)` can raise a window but can't list windows, reach their models or serve an untitled document.

## Consequences

- **Easier:** other cross-window actions have a route. Each window's composition root doesn't change.
- **Harder:**
  - `WindowRaiser` is a second AppKit dependency checked only by hand. So are the appear and disappear timings, which a later SwiftUI release could change.
  - `OpenExperiments` holds a strong reference to each model until its window disappears.
- **Revisit:**
  - If SwiftUI gains a way to bring a `DocumentGroup` window forward, remove `WindowRaiser`.
  - Two experiments with the same title look alike in the menu.
