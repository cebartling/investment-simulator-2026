# ADR-0005: Persist Scenarios as Versioned JSON Documents in a Document-Based App

**Status:** Accepted
**Date:** 2026-10-23
**Deciders:** Christopher Bartling

## Context

ADR-0001 deliberately left the persistence choice open and made it a driven adapter behind a port. The choice now needs making, because it also determines the app's shape on macOS.

A simulation is naturally a self-contained *scenario*: starting balances, contributions, assumptions and chosen projections. Users will want several scenarios, to compare them, to keep them, and possibly to share them.

On macOS, a document-based app (`DocumentGroup` with `FileDocument`) gives multi-window, Open/Save/Revert, autosave, undo integration and Finder file association with little code. An app-managed database gives a single library view but none of that.

The build is SwiftPM-only with a hand-assembled bundle, so anything that needs declarations in `Info.plist` (document types, exported UTIs) must be added there manually.

## Decision

- **The app is document-based.** A scenario is one document, shown through `DocumentGroup`. There is no app-wide database.
- **The on-disk format is versioned, human-readable JSON** with a top-level `schemaVersion` field and the file extension `.invsim` (exported as a custom `UTType` conforming to `public.json`).
- **Persistence DTOs are separate from domain types.** A driven adapter target, `InvestmentSimulatorPersistence`, depends on Core. It defines Codable DTOs per schema version, a codec that maps DTOs to and from Core's `Scenario`, and migrations from older versions. Core never imports it and never sees `Codable` file concerns.
- **Core owns the port.** Core defines a small, synchronous `ScenarioCoding` port (encode and decode a `Scenario` to and from `Data`). It is synchronous because `FileDocument` reads and writes synchronously (see ADR-0003). The `FileDocument` in the app target is a thin wrapper that calls it; it holds no format knowledge. It is declared `nonisolated`, because SwiftUI may read and write documents off the main actor while the app target defaults to main-actor isolation.
- **The codec is tested with plain `Data`** in an `InvestmentSimulatorPersistenceTests` target, including decoding each older schema version through its migration.
- **No SwiftData and no SQLite for now.**
- **`Info.plist` declares the document type and exported UTI,** and `just bundle` carries them into the app bundle.

## Options Considered

### Option A: Document-based app with versioned JSON files (chosen)

**Pros:**
- Native macOS behavior (multi-window, autosave, undo, Open Recent, Finder association) for little code.
- Files are portable, diffable, and easy to share or back up.
- Simple, with no schema migration engine or database dependency.

**Cons:**
- No built-in library or cross-scenario querying; comparing scenarios means opening several documents.
- Format versioning and migrations are our job.
- Document types need manual `Info.plist` work, and file association only works from the bundled `.app`, not `swift run`.

### Option B: App-managed JSON files in Application Support behind a repository port

**Pros:**
- Single-window library UI is straightforward.
- Same DTO and codec design as Option A.

**Cons:**
- Gives up document-app behavior; autosave, undo and file handling become hand-built.
- Sharing a scenario requires an explicit import and export feature.

### Option C: SwiftData

**Pros:**
- Apple-supported persistence with query support and little code.

**Cons:**
- Ties persistence to a framework whose models are classes and macros, so mapping to domain value types is still needed.
- Hides the storage format, which makes sharing and diffing harder.
- Schema migration behavior is harder to control and test.

### Option D: SQLite (for example GRDB)

**Pros:**
- Strong querying and performance for large datasets.

**Cons:**
- Adds a third-party dependency and a schema to maintain for a small data set.
- Overkill unless scenarios or price histories become large.

## Consequences

- **Easier:** multi-window comparison, native file handling, sharing files, and testing the codec with plain `Data`.
- **Harder:** designing a stable file format early; maintaining migrations; testing document behavior without UI tests.
- **Revisit:**
  - If a cross-scenario library, search or large market-data history is needed, add a database adapter in a new ADR.
  - Whether `ReferenceFileDocument` is needed for undo with a presentation model.
  - Whether sandboxing and entitlements are required, which depends on the distribution route in ADR-0006.
