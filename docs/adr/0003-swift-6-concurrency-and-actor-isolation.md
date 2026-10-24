# ADR-0003: Swift 6 Concurrency and Actor Isolation

**Status:** Accepted
**Date:** 2026-10-23
**Deciders:** Christopher Bartling

## Context

`Package.swift` uses `swift-tools-version: 6.2`, so every target builds in Swift 6 language mode with complete data-race checking. The project needs a deliberate concurrency model rather than fixing diagnostics one at a time.

Two kinds of code have different needs:

- **Core** holds domain logic and simulations, which can be CPU-heavy (many scenarios, many periods). It must not depend on the main thread or on UI frameworks.
- **The app target** is SwiftUI and AppKit code, which is main-actor bound almost everywhere.

Swift 6.2 lets a target set its default actor isolation (`.defaultIsolation(MainActor.self)`) and opt in to nonisolated-nonsending async semantics. This removes most `@MainActor` annotations from UI code without weakening checking.

## Decision

- **Swift 6 language mode stays on for all targets.** No target drops to Swift 5 mode and no `@preconcurrency` or `nonisolated(unsafe)` is added without a comment explaining why.
- **Core uses the default (nonisolated) isolation.** Domain types are value types and `Sendable`. Use cases are `async` where they do work that may take time, and plain synchronous functions where they are pure.
- **The app target (and any presentation target) sets `defaultIsolation(MainActor.self)`.** Views and presentation models are main-actor isolated without annotations. Types in those targets that SwiftUI calls off the main actor, such as the `FileDocument` (ADR-0005), are declared `nonisolated`.
- **Driven ports are `Sendable` protocols, and `async` when they do I/O or may take time** (prices, storage). Pure, fast transformations stay synchronous, notably `ScenarioCoding` (ADR-0005), which SwiftUI's synchronous `FileDocument` read and write must call. Adapters hide their own isolation (an actor, a serial queue, or main-actor access) behind the port.
- **Heavy simulation runs off the main actor using structured concurrency** (`async let`, `TaskGroup`), not `DispatchQueue` or detached tasks. Cancellation is checked in long loops so the UI can cancel a run.
- **Combine is not used.** State flows through `@Observable` and `async` calls, and streams use `AsyncSequence`.
- **No global mutable state.** This also supports the no-singletons rule in ADR-0001.

## Options Considered

### Option A: Nonisolated Core, main-actor-by-default app (chosen)

**Pros:**
- Keeps Core UI-free and free to run on any executor, which suits CPU-heavy simulation.
- Removes `@MainActor` noise from UI code.
- The compiler enforces data-race safety across the Core and app boundary.

**Cons:**
- Two default isolations in one codebase; contributors must know which target they are in.
- Core types must be `Sendable`, which pushes toward value types and immutability (mostly a benefit here).
- Default-isolation settings are relatively new and may change behavior between toolchains.

### Option B: Swift 5 language mode with minimal checking

**Pros:**
- Fewer diagnostics up front.

**Cons:**
- Gives up compile-time data-race safety, and a later migration would be larger.
- Not needed on a new codebase.

### Option C: `@MainActor` default for every target, including Core

**Pros:**
- One rule everywhere; simplest mental model.

**Cons:**
- Forces simulation work to hop to the main actor or be explicitly marked `nonisolated`, which fights the purpose of Core.
- Makes Core harder to reuse in a CLI or background process, which weakens ADR-0001.

### Option D: Combine and `DispatchQueue`

**Pros:**
- Familiar to long-time Apple developers.

**Cons:**
- No compiler-checked isolation, more boilerplate, and a poor fit with `@Observable`.

## Consequences

- **Easier:** reasoning about threads, cancelling long simulations, and testing async code with Swift Testing.
- **Harder:** every port and domain type must be `Sendable`; adapters that wrap non-`Sendable` framework types need an actor or a careful boundary.
- **Revisit:**
  - Whether to enable further upcoming Swift features beyond those 6.2 enables by default.
  - Whether simulation parallelism needs a custom executor or limits on concurrent tasks.
