# ADR-0004: `@Observable` Presentation Models and Dependency Injection into SwiftUI

**Status:** Accepted
**Date:** 2026-10-23
**Deciders:** Christopher Bartling

## Context

ADR-0001 makes the SwiftUI layer the driving adapter and says the app target is the composition root, with dependencies injected through initializers. It does not say how views get state from use cases, where screen logic lives, or how injection works inside the SwiftUI view tree.

Two constraints shape the answer:

- Only `InvestmentSimulatorCore` has tests today. Logic placed in the app target, such as "what the screen shows after a run fails", cannot be unit tested.
- The project builds with SwiftPM only (no Xcode project, no previews, no UI tests), so views are hard to test and should stay thin.

Observation (`@Observable`) is part of the Swift standard library, not SwiftUI, so a UI-free target can use it.

## Decision

- **Screens are driven by `@Observable` presentation models** (one per screen or feature). A presentation model holds UI state, exposes intent methods such as `runSimulation()`, calls Core use cases through their driving ports, and maps domain results and errors to display state. `ObservableObject`, `@Published` and Combine are not used.
- **Presentation models live in their own SwiftPM library target, `InvestmentSimulatorPresentation`,** which depends on Core and imports only Foundation and Observation, never SwiftUI or AppKit. This makes them unit testable. A test target `InvestmentSimulatorPresentationTests` covers them with fake use cases.
- **Views are thin and declarative.** They read state from a presentation model and call its methods. They own only ephemeral view state (`@State` for focus, selection, sheet presentation). They contain no domain or formatting rules beyond using `FormatStyle`.
- **Injection uses initializers.** The app's composition root builds adapters, use cases and the root presentation model, and passes models down through view initializers. A child screen's model is created by its parent or by the composition root, not by the child.
- **`@Environment` is used sparingly,** only to pass the root application model (or other UI-level concerns like a theme) down a deep tree. Adapters and Core services are never placed in the environment, and no view reads one from a global.
- **Models own `@MainActor` isolation through the target's default isolation** (see ADR-0003); heavy work is awaited from Core and never run on the main actor.

## Options Considered

### Option A: Presentation models in a separate UI-free target (chosen)

**Pros:**
- Screen logic is unit testable without SwiftUI, an app launch, or an Xcode UI test.
- Keeps views thin, which suits a project with no previews.
- The target boundary stops presentation code importing SwiftUI by accident.

**Cons:**
- A third library target and a new test target to maintain.
- Some indirection, since small screens may not need a model of their own.

### Option B: Presentation models in the app target

**Pros:**
- Fewer targets; simplest structure.

**Cons:**
- Screen logic cannot be tested without making the executable target testable, which is awkward in SwiftPM.
- Easier for UI and presentation concerns to blur.

### Option C: No presentation layer; views bind to Core models and call use cases directly

**Pros:**
- Least code, closest to Apple's samples.

**Cons:**
- Screen logic ends up in views, untested.
- Core types would need to be `@Observable`, which couples the domain to a UI-oriented mechanism.

### Option D: Service injection through `@Environment` everywhere

**Pros:**
- Convenient in deep view trees, and idiomatic SwiftUI.

**Cons:**
- Dependencies become implicit and fail at runtime when missing, which conflicts with ADR-0001's explicit initializer injection.
- Easy to turn into a service locator.

## Consequences

- **Easier:** testing screen behavior, keeping views simple, and replacing use cases with fakes.
- **Harder:** more types and wiring per screen; two test targets.
- **Revisit:**
  - Whether `@Environment` for the root model is worth it or whether initializer passing alone is enough.
  - Whether simple screens may skip a presentation model.
