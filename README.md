# investment-simulator-2026
Investments simulator built in Swift and SwiftUI

## Requirements

- macOS 26+
- Swift 6.2+ toolchain (Xcode or Command Line Tools installed; the Xcode IDE is not used)
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
