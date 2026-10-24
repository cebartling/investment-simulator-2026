# ADR-0006: SwiftPM-Only Build and Hand-Assembled App Bundle

**Status:** Accepted
**Date:** 2026-10-23
**Deciders:** Christopher Bartling

_This ADR records a decision already in effect (see `CLAUDE.md`, `Package.swift` and `justfile`). It was written retroactively._

## Context

The app is a macOS SwiftUI app. The conventional setup is an Xcode project, but the project wants a build that is scriptable, reproducible in CI, diff-friendly, and driven from a terminal and by agents, without opening Xcode.

SwiftPM can build an executable target but does not produce an `.app` bundle. A bare executable launched from SwiftPM starts as a background process, so the app needs a bundle with an `Info.plist` and a code signature to behave like a normal Mac app.

Xcode itself must still be installed and selected: Command Line Tools alone lack the Swift Testing module and the SwiftUI `#Preview` macro plugin.

## Decision

- **The build is SwiftPM only.** There is no `.xcodeproj` or `.xcworkspace`, and the Xcode IDE is not used.
- **The `justfile` is the single entry point** for build, test, run, bundle, format, lint and clean. CI runs the same recipes.
- **`just bundle` assembles the `.app` by hand:** a release build, the executable copied into `Contents/MacOS`, `Resources/Info.plist` copied into `Contents`, and an ad-hoc `codesign`.
- **`AppDelegate` promotes the process to a regular app** (`setActivationPolicy(.regular)` in `applicationWillFinishLaunching`) so `swift run` shows a Dock icon and working menu bar.
- **No `#Preview` blocks.** They render only in the Xcode IDE, which is not used, so they would be dead code.
- **Formatting, linting and CI are decided separately,** in ADR-0008 and ADR-0009.
- **Names stay in sync by convention.** The app and executable name appear in `AppMetadata.displayName`, `Info.plist` and the `justfile`; they are changed together.

## Options Considered

### Option A: SwiftPM plus `justfile` and a scripted bundle (chosen)

**Pros:**
- Everything is plain text and diff-friendly; no generated or merge-conflict-prone project file.
- Builds the same way locally and in CI, and is easy for scripts and agents to drive.
- Few moving parts: SwiftPM, `just`, `codesign`.

**Cons:**
- No SwiftUI previews and no Interface Builder-style tooling.
- Resources Xcode would normally process (asset catalogs, app icon sets, `.xcstrings` compilation, entitlements) need manual handling.
- No XCUITest, because there is no UI test target type in SwiftPM.
- Distribution is not covered: Developer ID signing, hardened runtime, notarization and entitlements must be scripted.
- Duplicated names can drift out of sync.

### Option B: Standard Xcode project

**Pros:**
- First-class tooling: previews, asset catalogs, entitlements UI, UI tests, archive and notarize workflow.
- Best-trodden path for macOS distribution.

**Cons:**
- The `.pbxproj` is noisy in version control and hard to edit by hand or by agents.
- Builds depend more on IDE settings and are harder to reproduce.

### Option C: Generated Xcode project (XcodeGen or Tuist) from a manifest

**Pros:**
- Text manifest with real Xcode project features, previews and UI tests.

**Cons:**
- Adds a generator and a second source of truth alongside `Package.swift`.
- More tooling to install and keep in step with Xcode releases.

## Consequences

- **Easier:** reproducible builds, simple CI, small reviewable diffs, and agent-driven workflows.
- **Harder:** anything Xcode automates, such as icons, localization resources, entitlements, notarization, and UI testing.
- **Revisit:**
  - Add Developer ID signing, hardened runtime and notarization to `just bundle` before any distribution outside this machine.
  - Single-source the app name, for example by generating `Info.plist` values from one variable.
  - If UI testing or asset catalogs become necessary, reconsider Option C.
