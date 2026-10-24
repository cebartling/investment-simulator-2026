# ADR-0007: Swift Testing and Core-Focused Test Strategy

**Status:** Proposed
**Date:** 2026-10-23
**Deciders:** Christopher Bartling

_This ADR records a decision already in effect (see `CLAUDE.md` and `Tests/`). It is written retroactively; change its status to Accepted once confirmed._

## Context

The project's value is in its domain logic (see ADR-0001), which needs fast, thorough tests. The build is SwiftPM only with no Xcode project (see ADR-0006), so Xcode-hosted test types such as XCUITest are not available.

Swift has two test frameworks: XCTest and Swift Testing (`import Testing`). Swift Testing needs the full Xcode toolchain; Command Line Tools alone fail with `no such module 'Testing'`, which the project already accepts as a requirement.

## Decision

- **Tests are written with Swift Testing** (`@Test`, `#expect`, `#require`, `@Suite`). XCTest is not used for new tests.
- **Core is the primary test target.** `InvestmentSimulatorCoreTests` holds the unit tests. Anything testable is placed in `InvestmentSimulatorCore`, which is why it has no UI imports.
- **Tests go through ports with in-memory fakes** for driven ports (see ADR-0001). No test touches the disk, network, real clock or system random source.
- **Table-driven logic uses parameterized tests** (`@Test(arguments:)`), for example for financial formulas across rates and horizons.
- **Test names are descriptive sentences** using raw identifiers, for example `` @Test func `display name is investment simulator`() ``. SwiftFormat's defaults produce this style (see ADR-0008).
- **Run commands:** `just test` for all tests; `swift test --filter <Suite>` or `--filter <Suite>/<test>` for one.
- **No UI tests.** View behavior is kept thin and tested through presentation models, where those exist (see ADR-0004).

## Options Considered

### Option A: Swift Testing, Core-focused (chosen)

**Pros:**
- Modern, concise syntax; parameterized tests and good failure output.
- Runs from the command line through SwiftPM, in CI and locally.
- Concentrates tests where the logic is.

**Cons:**
- Requires the full Xcode toolchain, not only Command Line Tools.
- Views and AppKit glue are not tested automatically.
- Newer than XCTest, so some tooling and examples are less common.

### Option B: XCTest

**Pros:**
- Mature, universal, works with Command Line Tools alone.
- Includes performance and UI testing APIs.

**Cons:**
- More boilerplate, no native parameterized tests, weaker failure diagnostics.
- The project already needs full Xcode, so the toolchain advantage does not apply.

### Option C: Swift Testing for Core plus XCUITest for the UI

**Pros:**
- Covers the UI end to end.

**Cons:**
- Needs an Xcode project and UI test target, which conflicts with ADR-0006.
- UI tests are slow and brittle for the value they add on a small app.

## Consequences

- **Easier:** testing domain logic quickly and in isolation; running one test from the terminal.
- **Harder:** anything in the app target is untested unless it moves into Core or a presentation target.
- **Revisit:**
  - If ADR-0004 is accepted, add `InvestmentSimulatorPresentationTests` and update `CLAUDE.md`, which says Core is the only target with tests.
  - Whether to add a coverage report to CI.
  - Whether to add snapshot or other UI checks if the view layer grows.
