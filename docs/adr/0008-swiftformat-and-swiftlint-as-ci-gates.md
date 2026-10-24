# ADR-0008: SwiftFormat and SwiftLint as CI Gates

**Status:** Accepted
**Date:** 2026-10-23
**Deciders:** Christopher Bartling

_This ADR records a decision already in effect (see `CLAUDE.md`, `justfile`, `.swiftlint.yml` and `.swift-version`). It was written retroactively._

## Context

Consistent style keeps diffs small and reviews about substance. Formatting (whitespace, trailing commas, import order) can be fully automated; linting (complexity, risky constructs, naming) cannot always be.

SwiftFormat and SwiftLint overlap on some rules and disagree on others. Trailing commas are the known case: SwiftFormat adds them by default and SwiftLint's `trailing_comma` rule forbids them. Without a decision, `just format` and `just lint` would fight each other.

Commands run from the command line and CI (see ADR-0006), so the tools must run without Xcode integration.

## Decision

- **SwiftFormat is the formatter and owns layout.** `just format` rewrites `Sources`, `Tests` and `Package.swift` in place.
- **SwiftLint is the linter and owns code-quality rules,** run with `--strict` so warnings fail the build.
- **Where they overlap, SwiftFormat wins and the SwiftLint rule is disabled.** `.swiftlint.yml` disables `trailing_comma` with a comment saying why. A new disabled rule needs the same comment.
- **SwiftFormat reads its target Swift version from `.swift-version`** (currently 6.2), so it and the toolchain agree. The two are updated together.
- **SwiftFormat defaults are kept** unless there is a reason to override, including the rewriting of Swift Testing function names to raw identifiers. There is no `.swiftformat` config file today; one is added only when an override is needed.
- **`just lint` runs both tools in check mode** (`swiftformat --lint`, `swiftlint lint --strict`) and CI fails on any violation. Paths are passed explicitly (`Sources Tests Package.swift`) so SwiftLint does not scan `.build/`.
- **Contributors run `just format` before committing;** CI does not auto-fix.

## Options Considered

### Option A: SwiftFormat plus SwiftLint, with SwiftFormat owning overlaps (chosen)

**Pros:**
- Formatting is automatic and never debated in review.
- SwiftLint catches things a formatter cannot.
- Clear rule for resolving conflicts keeps the tools from fighting.

**Cons:**
- Two tools to install and keep current (both installed with Homebrew in CI).
- Version differences between local and CI can cause unexpected violations.
- Overlaps must be found and disabled by hand.

### Option B: SwiftLint only (with its autocorrect)

**Pros:**
- One tool and one config.

**Cons:**
- Autocorrect covers fewer formatting rules and is less thorough than a real formatter.

### Option C: Apple's `swift-format`

**Pros:**
- Maintained by Apple and ships with recent toolchains, so no extra install.

**Cons:**
- Fewer rules and less configuration flexibility; no lint-only rules like SwiftLint's.
- Would still leave the linting need unmet.

### Option D: No enforced style

**Pros:**
- No tooling cost.

**Cons:**
- Style drift and noisy diffs, especially when agents and people both edit code.

## Consequences

- **Easier:** reviews focus on substance; style is machine-checked in CI.
- **Harder:** tool versions can drift between machines; overlap rules need maintenance when either tool changes.
- **Revisit:**
  - Pin tool versions (for example with a `Brewfile` or mint) if version drift causes CI surprises.
  - Whether to add a SwiftLint custom rule that fails if Core imports a UI or persistence framework (see ADR-0001, "Revisit").
  - Whether to adopt a `.swiftformat` config once defaults need overriding.
