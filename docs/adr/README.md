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
| [0005](0005-scenario-persistence-and-document-based-app.md) | Persist Scenarios as Versioned JSON Documents in a Document-Based App | Superseded by ADR-0021 |
| [0006](0006-swiftpm-only-build-and-hand-assembled-app-bundle.md) | SwiftPM-Only Build and Hand-Assembled App Bundle | Accepted |
| [0007](0007-swift-testing-and-test-strategy.md) | Swift Testing and Core-Focused Test Strategy | Accepted |
| [0008](0008-swiftformat-and-swiftlint-as-ci-gates.md) | SwiftFormat and SwiftLint as CI Gates | Accepted |
| [0009](0009-github-actions-ci-on-pinned-xcode-runner.md) | GitHub Actions CI on a Pinned Xcode Runner | Accepted |
| [0010](0010-native-swiftui-window-management.md) | Native SwiftUI Window Management, with `WindowGroup` Until `DocumentGroup` | Superseded by ADR-0011 |
| [0011](0011-document-window-management.md) | Document Window Management, with One AppKit Close | Superseded by ADR-0021 |
| [0012](0012-market-data-and-secrets.md) | Market Data from Equibles, with the API Key in the Keychain | Accepted |
| [0013](0013-limit-order-fills-from-daily-bars.md) | Fill Limit Orders from Daily Bars, at the Limit Price | Accepted |
| [0014](0014-buy-limit-orders-and-cancellation.md) | Buy Limit Orders, Reserved Cash and Order Cancellation | Accepted |
| [0015](0015-experiment-identity-and-holdings-quotes.md) | Experiment Name, Notes and Created Date, and Quoting Holdings on Open | Accepted |
| [0016](0016-market-sales-and-realized-gain.md) | Market Sales and Realized Gain | Accepted |
| [0017](0017-app-icon-from-icon-composer-source.md) | App Icon from an Icon Composer Source | Accepted |
| [0018](0018-release-and-distribution.md) | Releases as Notarized Zips on GitHub, Built from Tags | Accepted |
| [0019](0019-research-window.md) | Research Window, Its Ports, and SEC EDGAR for Tickers | Accepted |
| [0020](0020-research-buy-in-experiment.md) | Buying from Research Through a Registry of Open Experiments | Superseded by ADR-0021 |
| [0021](0021-sqlite-library-replaces-document-persistence.md) | Store Experiments in an App-Wide SQLite Database, in a Single Library Window | Accepted |
| [0022](0022-stock-cards.md) | Show an Experiment's Stocks as Cards, Selling from a Chosen Purchase | Accepted |
| [0023](0023-stock-card-live-quote.md) | Show a Stock's Quote, Change and Unrealized Gain on Its Card's Overview | Accepted |
| [0024](0024-trade-times-on-stock-cards.md) | Show When Each Trade Was Priced on Its Stock Card | Accepted |
| [0025](0025-money-to-the-cent.md) | Show Money to the Cent, with the Full Value on Hover | Accepted |
