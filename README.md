# investment-simulator-2026

[![CI](https://github.com/cebartling/investment-simulator-2026/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/cebartling/investment-simulator-2026/actions/workflows/ci.yml)

Investments simulator built in Swift and SwiftUI

## Requirements

- macOS 26+
- Xcode installed and selected (`xcode-select -p`); it supplies the Swift 6.2+ toolchain and the Swift Testing module. The Xcode IDE itself is never opened. Command Line Tools alone are not enough: `swift test` fails with `no such module 'Testing'`.
- [just](https://github.com/casey/just), [SwiftFormat](https://github.com/nicklockwood/SwiftFormat), [SwiftLint](https://github.com/realm/SwiftLint): `brew install just swiftformat swiftlint`

## Commands

| Command       | Description                                        |
| ------------- | -------------------------------------------------- |
| `just build`  | Debug build                                        |
| `just test`   | Run the test suite (Swift Testing)                 |
| `just run`    | Launch the app directly from SwiftPM               |
| `just bundle` | Build an ad-hoc signed release `.app` in `build/`  |
| `just open`   | Build the `.app` bundle and open it                |
| `just format` | Format sources in place                            |
| `just lint`   | Check formatting and lint                          |
| `just clean`  | Remove build artifacts                             |

## Layout

- `Sources/InvestmentSimulatorCore`: UI-free logic, covered by tests
- `Sources/InvestmentSimulator`: SwiftUI app entry point and views
- `Tests/InvestmentSimulatorCoreTests`: Swift Testing suites
- `Resources/Info.plist`: bundle metadata used by `just bundle`
- `docs/adr/`: Architecture Decision Records, starting with [ADR-0001: Hexagonal Architecture](docs/adr/0001-hexagonal-architecture.md)
