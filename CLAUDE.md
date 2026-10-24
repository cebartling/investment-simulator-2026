# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build system

This is a macOS SwiftUI app built entirely from the command line with Swift Package Manager. There is no `.xcodeproj` and the Xcode IDE is never used, but Xcode must be installed and selected: Command Line Tools alone lack the Swift Testing module (`no such module 'Testing'`) and the SwiftUI `#Preview` macro plugin. Do not add `#Preview` blocks; they break builds without Xcode.app and have no use here.

All tasks go through the `justfile`:

- `just build`: debug build
- `just test`: run all tests (Swift Testing)
- `swift test --filter AppMetadataTests`: run a single suite (or `--filter <Suite>/<test>`)
- `just run`: launch the app straight from SwiftPM
- `just bundle`: release build wrapped into an ad-hoc signed `build/Investment Simulator.app`
- `just open`: bundle, then open the `.app`
- `just format`: SwiftFormat in place
- `just lint`: SwiftFormat in lint mode plus `swiftlint lint --strict`; CI fails on any violation
- `just clean`: `swift package clean` plus removing `build/`

## Architecture

The project follows Hexagonal Architecture ([ADR-0001](docs/adr/0001-hexagonal-architecture.md)). Decisions are recorded as ADRs in `docs/adr/`; read them before changing structure, and add one for any new architectural decision.

Targets (those marked *planned* don't exist yet; create each one with its test target when the first code needs it):

- `InvestmentSimulatorCore` (library): the hexagon. Domain model, use cases, and ports as protocols. Imports only Foundation, never SwiftUI, AppKit, SwiftData or networking. Put anything testable here.
- `InvestmentSimulatorPresentation` (library, ADR-0004): `@Observable` presentation models, one per screen. Depends on Core; imports only Foundation, Observation and Core, never SwiftUI or AppKit.
- `InvestmentSimulatorPersistence` (library, ADR-0005): versioned JSON DTOs, the codec implementing Core's `ExperimentCoding` port, and schema migrations. Money is stored as a decimal string, never a JSON number.
- `InvestmentSimulator` (executable): thin SwiftUI views and the composition root, which builds adapters and presentation models and passes them down through initializers. Adapters and services never go in `@Environment`. The app has no tests.
- Every library target has a matching `…Tests` target using Swift Testing (ADR-0007). Driven ports are faked in memory; no test touches disk, network, the real clock or system randomness.

**Terminology:** ADR-0005 says *scenario*; the code and UI say *experiment* (`Experiment`, `ExperimentCoding`). They are the same concept.

Rules from the accepted ADRs:

- **Money (ADR-0002):** amounts are Core's `Money` type wrapping `Decimal`, never `Double`, and `Money` is not `Codable`. Rates are `Decimal`; stochastic samples are `Double` only inside the engine. Round to cents with banker's rounding only at reporting boundaries, through `Money`. Core never formats display strings.
- **Concurrency (ADR-0003):** Swift 6 mode everywhere. Core is nonisolated with `Sendable` value types. The app and Presentation targets set `defaultIsolation(MainActor.self)` in `Package.swift`. Mark types SwiftUI calls off the main actor, like the `FileDocument`, `nonisolated`. Driven ports are `async` when they do I/O. Use structured concurrency for heavy simulation, with cancellation checks. No Combine, `ObservableObject`, `DispatchQueue` or global mutable state.
- **Persistence (ADR-0005):** document-based app (`DocumentGroup`), one experiment per `.invsim` JSON file with a `schemaVersion`. No SwiftData or SQLite. Document types and the exported UTI (`com.cebartling.InvestmentSimulator.experiment`) go in `Resources/Info.plist`. `ExperimentDocument` reaches the codec through an immutable `static let`, because SwiftUI constructs `FileDocument`s itself; that is the one exception to initializer injection.
- **Windows (ADR-0010):** each window's root view (`MainWindow`) is its own composition root and creates its own presentation model; windows share no UI state. SwiftUI persists window frames, keyed on the root view's type name, so renaming it resets users' saved frames once. Configure windows only through SwiftUI scene and view modifiers: no `NSWindow` access, autosave names or custom frame storage. The one exception is `WindowCloser` (ADR-0011), which closes a cancelled new document because SwiftUI's dismiss actions can't. Before planning window-state code, check what SwiftUI already does against the bundled app.

`AppDelegate` sets the activation policy to `.regular` in `applicationWillFinishLaunching`. A bare SwiftPM executable otherwise launches as a background process with no Dock icon and an unresponsive menu bar. Setting it later, in `didFinishLaunching`, is too late.

`just bundle` assembles the `.app` by hand from `Resources/Info.plist` plus the release binary. The app name and executable name are duplicated across `AppMetadata.displayName`, `Info.plist` (`CFBundleName`, `CFBundleDisplayName`, `CFBundleExecutable`) and the `justfile` (`app_name`, `app_bundle`). Change them together, or the bundle will not launch.

## Formatting and lint

- SwiftFormat reads its target Swift version from `.swift-version` (6.2). Its defaults rename Swift Testing functions to raw identifiers, e.g. `` @Test func `display name is investment simulator`() ``.
- SwiftFormat owns trailing-comma style, so `.swiftlint.yml` disables SwiftLint's `trailing_comma` rule.
- Pass explicit paths to SwiftLint (as `just lint` does); otherwise it scans `.build/`.

## CI

`.github/workflows/ci.yml` runs `just lint`, `just test` and `just bundle` on pushes to `main` and on pull requests. It uses the `xcode-27` runner, a GitHub public-preview image, and selects `/Applications/Xcode_27.1.app` to match the local toolchain. When that Xcode is removed from the image, update the path.
