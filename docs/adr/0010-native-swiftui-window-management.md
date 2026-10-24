# ADR-0010: Native SwiftUI Window Management, with `WindowGroup` Until `DocumentGroup`

**Status:** Accepted; amended by ADR-0011
**Date:** 2026-10-24
**Deciders:** Christopher Bartling

## Context

ADR-0005 makes the app document-based (`DocumentGroup`), but no scenario document exists yet. Until it does, the app needs some other scene to host the main window. Today that is `WindowGroup(AppMetadata.displayName)` in `InvestmentSimulatorApp.swift`, whose root view `MainWindow` creates a `MainWindowModel` in `@State`. A code comment explains this choice, but no ADR records it.

ADR-0001 makes the app target the composition root, and ADR-0004 governs how models are passed down. Neither says what the composition root is scoped to. `@State` on the `App` is shared by every window `WindowGroup` opens, so an app-level model would let windows step on each other's selection and state.

Window state such as size and position came up in PIN-397. The plan there assumed SwiftUI restores frames only through state restoration, which macOS turns off when "Close windows when quitting an app" is on (the default), so it proposed AppKit frame autosave through an `NSViewRepresentable`. Testing on 2026-10-24 disproved the assumption:

- `WindowGroup` sets its own frame autosave name on each window and stores the frame in `UserDefaults` under `NSWindow Frame InvestmentSimulator.MainWindow-1-AppWindow-1`.
- It restores that frame on every launch, whatever the "Close windows when quitting" setting.
- SwiftUI replaced a custom `setFrameAutosaveName`, so the shim did nothing.

The key comes from the root view's type name. A stale `InvestmentSimulator.ContentView-1-AppWindow-1` key shows that PIN-396 reset every saved frame when the root view changed from `ContentView` to `MainWindow`.

## Decision

- **Use `WindowGroup` until the scenario document lands, then replace it with `DocumentGroup` (ADR-0005).** The switch comes with the first `FileDocument`, not before.
- **Scope the composition root to a window.** Each window's root view (`MainWindow` today, the document's root view later) creates its own presentation model, so windows share no UI state. App-wide services, once they exist, are built once at the `App` level and passed into each window's root view through its initializer (ADR-0004). They never go in `@Environment`.
- **Window frame and placement come from SwiftUI and AppKit's built-in persistence.** Windows are configured only through SwiftUI scene and view modifiers, such as `.defaultSize`, `.windowResizability`, `.defaultWindowPlacement`, `.restorationBehavior` and `frame` constraints. The app adds no `NSWindow` access, autosave names or custom frame storage.
- **Check native behavior first.** A new window-state requirement starts with an experiment against the bundled app (`just open`), reading `UserDefaults` and real window bounds, before any custom code is planned.

## Options Considered

### Option A: Native SwiftUI window management, per-window composition root (chosen)

**Pros:**
- No code to write, test or maintain for frame persistence, which works whatever the "Close windows when quitting" setting.
- Behavior matches other macOS apps, including cascading new windows.
- A per-window model maps directly onto one model per document once `DocumentGroup` arrives.

**Cons:**
- The autosave key is SwiftUI's private format, built from the root view's type name. Renaming that view loses every user's saved frame once, and moving to `DocumentGroup` likely does too (untested).
- Restoration can be turned on or off (`.restorationBehavior`), but the app can't control the autosave key or how frames are matched. If SwiftUI changes that, the app changes with it.

### Option B: Custom frame persistence (AppKit autosave or a stored frame)

**Pros:**
- A stable key the app owns, which survives view renames and the move to `DocumentGroup`.
- Full control, e.g. per-document frames.

**Cons:**
- SwiftUI replaces `setFrameAutosaveName`, so this needs workarounds that fight the framework.
- It lives in the app target, which has no tests (ADR-0007), so it could only be verified by hand.
- It solves a problem that, as of PIN-397, doesn't exist.

### Option C: Adopt `DocumentGroup` now, before a scenario document exists

**Pros:**
- Matches ADR-0005 immediately, so the scene type changes only once, along with any frame reset that change brings.

**Cons:**
- Needs a placeholder `FileDocument`, document types and an exported UTI with nothing real to save, which is speculative code.
- Brings in Open/Save UI and the untitled-document flow before the app can do anything with them.

### Option D: A single app-level presentation model shared by all windows

**Pros:**
- Simplest wiring: one model, created once.

**Cons:**
- Every window shares its selection and state, so opening a second window can't show anything different.
- Doesn't map onto one model per document.

## Consequences

- **Easier:** no window-management code; new windows behave like native macOS windows; the per-window root carries straight over to `DocumentGroup`.
- **Harder:**
  - Renaming the root view resets saved window frames once. The `WindowGroup` to `DocumentGroup` switch likely does too; verify it when that lands. Treat both as user-visible changes.
  - `just run` and `just open` keep their saved frames in separate `UserDefaults` domains, so their window positions differ.
- **Revisit:**
  - When `DocumentGroup` lands, check that per-document frames behave as expected; if they don't, supersede this ADR.
  - If a requirement appears that native persistence can't meet, such as frames that survive a view rename, supersede this ADR instead of adding a workaround.
