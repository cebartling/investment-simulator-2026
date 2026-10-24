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

## Architecture

The project follows Hexagonal Architecture ([ADR-0001](docs/adr/0001-hexagonal-architecture.md)). Decisions are recorded as ADRs in `docs/adr/`; read them before changing structure, and add one for any new architectural decision.

- `InvestmentSimulatorCore` (library): the hexagon. Domain model, use cases, and ports as protocols. Imports only Foundation, never SwiftUI, AppKit, SwiftData or networking. This is the only target with tests, so put anything testable here.
- `InvestmentSimulator` (executable): the SwiftUI driving adapter and the composition root, which builds adapters and injects them into Core through initializers. Depends on Core.
- Driven adapters (persistence, market data) each get their own SwiftPM target that depends on Core, added only when a real adapter is needed. Core never depends on them.
- `InvestmentSimulatorCoreTests`: Swift Testing suites for Core.

`AppDelegate` sets the activation policy to `.regular` in `applicationWillFinishLaunching`. A bare SwiftPM executable otherwise launches as a background process with no Dock icon and an unresponsive menu bar. Setting it later, in `didFinishLaunching`, is too late.

`just bundle` assembles the `.app` by hand from `Resources/Info.plist` plus the release binary. The app name and executable name are duplicated across `AppMetadata.displayName`, `Info.plist` (`CFBundleName`, `CFBundleDisplayName`, `CFBundleExecutable`) and the `justfile` (`app_name`, `app_bundle`). Change them together, or the bundle will not launch.

## Formatting and lint

- SwiftFormat reads its target Swift version from `.swift-version` (6.2). Its defaults rename Swift Testing functions to raw identifiers, e.g. `` @Test func `display name is investment simulator`() ``.
- SwiftFormat owns trailing-comma style, so `.swiftlint.yml` disables SwiftLint's `trailing_comma` rule.
- Pass explicit paths to SwiftLint (as `just lint` does); otherwise it scans `.build/`.

## CI

`.github/workflows/ci.yml` runs `just lint`, `just test` and `just bundle` on pushes to `main` and on pull requests. It uses the `xcode-27` runner, a GitHub public-preview image, and selects `/Applications/Xcode_27.1.app` to match the local toolchain. When that Xcode is removed from the image, update the path.
