# Architecture Decision Records

Each significant architectural decision is recorded here as a numbered ADR.

## Adding an ADR

1. Copy `template.md` to `NNNN-short-title.md`, using the next number.
2. Fill it in with status `Proposed`; change it to `Accepted` once the decision is made.
3. Add it to the index below.

ADRs are not edited after acceptance except to change their status. To reverse a decision, write a new ADR and mark the old one `Superseded by ADR-NNNN`.

## Index

| ADR | Title | Status |
| --- | ----- | ------ |
| [0001](0001-hexagonal-architecture.md) | Adopt Hexagonal Architecture | Accepted |
| [0002](0002-money-and-numeric-representation.md) | Represent Money as Decimal in a `Money` Value Type | Accepted |
| [0003](0003-swift-6-concurrency-and-actor-isolation.md) | Swift 6 Concurrency and Actor Isolation | Accepted |
| [0004](0004-observable-presentation-models-and-dependency-injection.md) | `@Observable` Presentation Models and Dependency Injection into SwiftUI | Accepted |
| [0005](0005-scenario-persistence-and-document-based-app.md) | Persist Scenarios as Versioned JSON Documents in a Document-Based App | Accepted |
| [0006](0006-swiftpm-only-build-and-hand-assembled-app-bundle.md) | SwiftPM-Only Build and Hand-Assembled App Bundle | Accepted |
| [0007](0007-swift-testing-and-test-strategy.md) | Swift Testing and Core-Focused Test Strategy | Accepted |
| [0008](0008-swiftformat-and-swiftlint-as-ci-gates.md) | SwiftFormat and SwiftLint as CI Gates | Accepted |
| [0009](0009-github-actions-ci-on-pinned-xcode-runner.md) | GitHub Actions CI on a Pinned Xcode Runner | Accepted |
| [0010](0010-native-swiftui-window-management.md) | Native SwiftUI Window Management, with `WindowGroup` Until `DocumentGroup` | Accepted |
