# ADR-0002: Represent Money as Decimal in a `Money` Value Type

**Status:** Accepted
**Date:** 2026-10-23
**Deciders:** Christopher Bartling

## Context

The simulator's output is dollar amounts: balances, contributions, withdrawals and projected values. Users compare these figures and may check them by hand, so they must be exact and reproducible.

`Double` cannot represent most decimal fractions exactly (`0.1 + 0.2 != 0.3`). Over a multi-decade simulation with monthly steps, small errors accumulate and produce results that differ from a spreadsheet by a few cents. Any rounding that happens implicitly is also hard to test.

Stochastic parts of the simulation (sampling returns from a distribution) are floating-point by nature. The decision needs to cover where each representation is used and where they meet.

Core imports only Foundation, so the solution must be available there. `Foundation.Decimal` is.

## Decision

- **Monetary amounts are a `Money` struct in Core**, wrapping `Foundation.Decimal`. It is `Sendable` and `Hashable`. It is not `Codable`: file formats are the persistence adapter's concern, which maps `Money` to and from its own DTOs (see ADR-0005). Arithmetic between `Money` values is defined on the type; multiplying by a rate takes a `Decimal`.
- **Rates, returns and percentages are `Decimal`** in the deterministic model. Randomly sampled returns are generated as `Double` inside the stochastic engine and converted to `Decimal` once, at the point they are applied to a balance.
- **Currency is USD only for now.** `Money` does not carry a currency code. If multi-currency is ever needed, that is a new ADR that supersedes this one.
- **Rounding is explicit and happens at defined boundaries.** Intermediate calculations keep full `Decimal` precision. Rounding to cents (banker's rounding, `.bankers`) is applied only where a value becomes a reported figure, such as a period-end balance, through one `Money` method rather than ad hoc.
- **Formatting is not Core's concern.** Presentation uses `Decimal.FormatStyle.Currency`; Core never produces display strings.
- **No `Double` appears in a public Core API for money.**

## Options Considered

### Option A: `Money` wrapping `Decimal` (chosen)

**Pros:**
- Exact decimal arithmetic; results match a hand or spreadsheet calculation.
- Available in Foundation, so Core's import rule holds.
- A dedicated type stops money being mixed up with plain numbers (rates, counts) at compile time.

**Cons:**
- `Decimal` is slower than `Double`, which matters for large Monte Carlo runs.
- `Decimal` has an awkward API (no `Numeric` ergonomics for every operation, limited math functions), so `Money` needs wrapper code.
- Converting between `Double` and `Decimal` at the stochastic boundary needs care.

### Option B: `Double` everywhere

**Pros:**
- Fastest and simplest; works with all math functions.

**Cons:**
- Binary rounding error accumulates and shows up as wrong cents.
- Tests need tolerance comparisons everywhere, which hides real bugs.
- Nothing separates money from other numbers.

### Option C: Integer minor units (`Int` cents)

**Pros:**
- Exact and very fast.
- Common practice in payment systems.

**Cons:**
- Compounding growth at fractional rates needs sub-cent precision, so cents are too coarse inside the simulation.
- Every rate multiplication forces a rounding decision at every step.
- Overflow handling is required for long horizons.

## Consequences

- **Easier:** exact, deterministic results and plain equality in tests; one place to define rounding.
- **Harder:** `Money` and conversion code to write and test; a likely performance cost in the stochastic engine.
- **Revisit:**
  - Measure Monte Carlo performance; if `Decimal` is too slow, move the inner loop to `Double` and convert at the edges only.
  - Whether multi-currency support is ever needed.
  - Whether the rounding mode should be configurable per scenario.
