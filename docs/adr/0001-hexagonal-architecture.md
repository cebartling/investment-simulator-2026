# ADR-0001: Adopt Hexagonal Architecture

**Status:** Accepted
**Date:** 2026-10-23
**Deciders:** Christopher Bartling

## Context

The investment simulator's value is its domain logic: modelling portfolios, contributions, returns and projections. That logic must be correct, so it needs fast, thorough unit tests.

Everything around it is likely to change. The UI is SwiftUI today. Persistence (files, SwiftData or something else) and any market-data source have not been chosen. If domain code calls those frameworks directly, it becomes hard to test without them and hard to swap them later.

The project already separates a UI-free `InvestmentSimulatorCore` library from the `InvestmentSimulator` app target, and only Core has tests. This ADR turns that split into a rule and says how the rest of the system attaches to Core.

## Decision

Follow Hexagonal Architecture (ports and adapters).

- **Core is the hexagon.** `InvestmentSimulatorCore` holds the domain model, the use cases that operate on it, and the ports. It imports only Foundation, never SwiftUI, AppKit, SwiftData or networking frameworks.
- **Ports are Swift protocols owned by Core.**
  - *Driving (inbound) ports* are the use cases the outside world calls, such as running a simulation.
  - *Driven (outbound) ports* are what Core needs from the outside world, such as saving a portfolio, fetching prices, or reading the current date.
- **Adapters live outside Core and depend on it.** The SwiftUI views are the driving adapter. Each driven adapter (persistence, market data) gets its own SwiftPM target that depends on Core and implements its port. These targets are added only when a real adapter is needed.
- **The app target is the composition root.** `InvestmentSimulator` builds the concrete adapters and passes them into Core through initializers. No singletons and no service locators.
- **Dependencies point inward.** SwiftPM enforces this: Core declares no dependency on any adapter target, so it cannot import one.
- **Core is tested through its ports.** Tests use in-memory fakes of driven ports; they need no UI, disk or network.

## Options Considered

### Option A: Hexagonal Architecture (chosen)

**Pros:**
- Domain logic is testable in isolation, with fast tests.
- UI, persistence and data sources can be replaced without touching Core.
- SwiftPM target boundaries enforce the dependency rule at compile time, not just by convention.
- Fits the existing Core/app split and the project's preference for dependency injection and protocols over singletons.

**Cons:**
- More types: a protocol per port plus an adapter per implementation.
- Mapping between domain types and framework types (for example, persistence models) is extra code.
- Indirection can feel heavy while the app is small.

### Option B: Layered architecture (UI → services → data)

**Pros:**
- Familiar and simple to explain.
- Less ceremony than ports and adapters.

**Cons:**
- The domain depends on the data layer, so testing domain logic needs persistence fakes at the wrong level or the real thing.
- Swapping persistence ripples upward through services.

### Option C: SwiftUI-centric, no explicit boundary

Views and `@Observable` models call SwiftData and other frameworks directly, as in Apple's sample code.

**Pros:**
- Least code and fastest to start.
- Matches most Apple documentation and samples.

**Cons:**
- Domain logic gets tangled with UI and persistence, and is hard to unit test.
- Changing frameworks means rewriting domain code.
- Gives up the Core/app split the project already has.

## Consequences

- **Easier:** testing simulation logic thoroughly, adding a second UI (such as a CLI) or a new data source, and deferring the persistence choice.
- **Harder:** small features touch more files (port, use case, adapter, wiring), and domain types must be mapped to and from framework types at adapter boundaries.
- **Revisit:**
  - Whether one target per driven adapter stays worthwhile as their number grows.
  - Whether to add a lint rule or test that fails if Core imports a UI or persistence framework, beyond what SwiftPM already enforces.
