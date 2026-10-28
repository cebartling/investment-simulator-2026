# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build system

This is a macOS SwiftUI app built entirely from the command line with Swift Package Manager. There is no `.xcodeproj` and the Xcode IDE is never used, but Xcode must be installed and selected: Command Line Tools alone lack the Swift Testing module (`no such module 'Testing'`) and the SwiftUI `#Preview` macro plugin. Do not add `#Preview` blocks; they break builds without Xcode.app and have no use here.

All tasks go through the `justfile`:

- `just build`: debug build
- `just test`: run all tests (Swift Testing)
- `swift test --filter MoneyTests`: run a single suite (or `--filter <Suite>/<test>`)
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
- `InvestmentSimulatorMarketData` (library, ADR-0012): the Equibles adapter implementing Core's `QuoteProviding` port over an injected `HTTPTransport`, so its tests never reach the network.
- `InvestmentSimulator` (executable): thin SwiftUI views and the composition root, which builds adapters and presentation models and passes them down through initializers. Adapters and services never go in `@Environment`. The app has no tests.
- Every library target has a matching `…Tests` target using Swift Testing (ADR-0007). Driven ports are faked in memory; no test touches disk, network, the real clock or system randomness.

**Terminology:** ADR-0005 says *scenario*; the code and UI say *experiment* (`Experiment`, `ExperimentCoding`). They are the same concept.

Rules from the accepted ADRs:

- **Money (ADR-0002):** amounts are Core's `Money` type wrapping `Decimal`, never `Double`, and `Money` is not `Codable`. Rates are `Decimal`; stochastic samples are `Double` only inside the engine. Round to cents with banker's rounding only at reporting boundaries, through `Money`, plus when normalizing typed money input (the New Experiment cash balance), where validation checks the rounded value. Core never formats display strings.
- **Concurrency (ADR-0003):** Swift 6 mode everywhere. Core is nonisolated with `Sendable` value types. The app and Presentation targets set `defaultIsolation(MainActor.self)` in `Package.swift`. Mark types SwiftUI calls off the main actor, like the `FileDocument`, `nonisolated`. Driven ports are `async` when they do I/O. Use structured concurrency for heavy simulation, with cancellation checks. No Combine, `ObservableObject`, `DispatchQueue` or global mutable state.
- **Persistence (ADR-0005):** document-based app (`DocumentGroup`), one experiment per `.invsim` JSON file with a `schemaVersion`. No SwiftData or SQLite. Document types and the exported UTI (`com.cebartling.InvestmentSimulator.experiment`) go in `Resources/Info.plist`. `ExperimentDocument` reaches the codec through an immutable `static let`, because SwiftUI constructs `FileDocument`s itself; that is the one exception to initializer injection. The codec writes the latest schema (version 6, with purchases, sell and buy limit orders, their fills and cancellations, and the experiment's optional name, notes and created date) and migrates older versions when reading; every version it has written must stay readable.
- **Market data and secrets (ADR-0012):** prices come from Equibles through `QuoteProviding`. Try the live quote, then fall back to the latest close on `403` or a `stale` quote. JSON prices pass through `Double` once, inside the adapter, via `Decimal(string: String(double))`. The API key lives only in the Keychain (`KeychainCredentialStore`, behind `CredentialStoring`) and is entered in the Settings scene, never in documents, `UserDefaults` or logs. App-wide services are built once in `InvestmentSimulatorApp` and passed to each window's initializer.
- **Limit-order fills (ADR-0013):** Equibles has no historical intraday prices, so orders fill from daily bars (`DailyPriceProviding`). The rule lives in Core (`Experiment.fillingLimitOrders(from:at:)`): the first session whose high reaches the limit fills the order at exactly the limit price. Only orders open when the check runs can fill, from sessions after the placement session and before today in New York; an order that expired unchecked never fills, because its shares may have been sold again. The user starts a check with the Check Orders button; nothing checks automatically.
- **Buy limit orders and cancellation (ADR-0014):** `BuyLimitOrder` is its own type, separate from the sell `LimitOrder`. An open buy order reserves its cost, so purchases and new buy orders spend only `Experiment.availableCash(at:)`, and `purchasing(_:at:)` takes the time of the purchase. A buy order fills under ADR-0013's session rules when a session's low reaches its limit, at exactly the limit. The fill becomes a `Purchase` with the order's id and a `limitOrderFill` price source. An open order of either side can be cancelled; `cancelledAt` is stored, and an order counts as open only before it, so rebuilding a saved experiment still checks each placement at its own time. A cancelled order never fills.
- **Experiment header (ADR-0015):** an experiment's `name`, `notes` and `createdAt` are optional; the title falls back to the document's `fileURL` name (read in the `DocumentGroup` body, so it follows Save As), then "Untitled". Reading a pre-v6 file sets `createdAt` to its earliest purchase or order placement. Starting cash and invested cost are derived in Core, never stored. Unlike Check Orders, held tickers are quoted automatically, through `HoldingsPricesModel`: when the window opens and when holdings grow (`.task(id: heldTickers)`), plus Refresh Prices; there's no polling. Total Value and Gain/Loss show "—" until every held ticker is priced, and each ticker keeps its last good quote.
- **Windows (ADR-0011, superseding ADR-0010):** each document window's root view (`MainWindow`) is its own composition root and creates its own presentation model from its document; windows share no UI state. Configure windows only through SwiftUI scene and view modifiers: no autosave names or custom frame storage, and no `NSWindow` access except `WindowCloser`, which closes a cancelled new document because SwiftUI's dismiss actions can't. `DocumentGroup` windows don't remember their frames (checked 2026-10-24); that regression from PIN-397 is tracked in PIN-399. Before planning window-state code, check what SwiftUI already does against the bundled app.
- **Sheets (PIN-405):** sheet forms use `.formStyle(.grouped)` and size to their content. A sheet can't be taller than its document window, so `ContentView`'s `minHeight` must fit the tallest sheet (Buy Limit or Sell Limit with every message showing, about nine rows); when a sheet gains rows, check it still fits without scrolling. The `minHeight` is 640, not 480, so both tables keep a few rows below the Experiment header (PIN-408).

`AppDelegate` sets the activation policy to `.regular` in `applicationWillFinishLaunching`. A bare SwiftPM executable otherwise launches as a background process with no Dock icon and an unresponsive menu bar. Setting it later, in `didFinishLaunching`, is too late.

`just bundle` assembles the `.app` by hand from `Resources/Info.plist` plus the release binary. The app name and executable name are duplicated across `Info.plist` (`CFBundleName`, `CFBundleDisplayName`, `CFBundleExecutable`) and the `justfile` (`app_name`, `app_bundle`). Change them together, or the bundle will not launch. ADR-0006 also lists `AppMetadata.displayName`; that type was removed once `DocumentGroup` took the app name from `Info.plist`.

## Formatting and lint

- SwiftFormat reads its target Swift version from `.swift-version` (6.2). Its defaults rename Swift Testing functions to raw identifiers, e.g. `` @Test func `display name is investment simulator`() ``.
- SwiftFormat owns trailing-comma style, so `.swiftlint.yml` disables SwiftLint's `trailing_comma` rule.
- Pass explicit paths to SwiftLint (as `just lint` does); otherwise it scans `.build/`.

## CI

`.github/workflows/ci.yml` runs `just lint`, `just test` and `just bundle` on pushes to `main` and on pull requests. It uses the `xcode-27` runner, a GitHub public-preview image, and selects `/Applications/Xcode_27.1.app` to match the local toolchain. When that Xcode is removed from the image, update the path.

CI pins SwiftFormat and SwiftLint by version and SHA-256 in `ci.yml`. When you upgrade either tool locally, update the version and checksum there to match, or CI and local lint can disagree.
