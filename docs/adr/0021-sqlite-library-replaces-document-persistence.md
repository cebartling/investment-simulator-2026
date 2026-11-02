# ADR-0021: Store Experiments in an App-Wide SQLite Database, in a Single Library Window

**Status:** Accepted
**Date:** 2026-11-02
**Deciders:** Christopher Bartling

Supersedes ADR-0005, ADR-0011 and ADR-0020. Amends ADR-0015 and ADR-0019. ADR-0010, already superseded by ADR-0011, stays so.

## Context

ADR-0005 made the app document-based: one experiment per `.invsim` JSON file, opened through `DocumentGroup`. That choice shaped a good deal of the app:

- **Window management (ADR-0011).** Each document window is its own composition root and shares no UI state. `WindowCloser` is the one AppKit exception, and `DocumentGroup` windows don't remember their frames (PIN-399).
- **Research to experiment routing (ADR-0020).** Research is a separate app-wide window, so it reaches an experiment only through the `OpenExperiments` registry and `WindowRaiser`, which is a second AppKit exception.
- **Persistence (ADR-0005).** A versioned JSON codec, seven schema versions that must all stay readable, and a title that falls back to the file name (ADR-0015).

The app now wants a library of experiments: see all of them, open one, delete one, and move to Research, in a single window. That fits a database better than a folder of files. It also removes the need for the registry, the raise logic and the per-window composition roots.

The experiment data is small, relational (purchases, sales, orders, fills, cancellations) and has one user on one machine. The app is distributed as a notarized zip (ADR-0018), not through the Mac App Store, so it isn't sandboxed.

## Decision

- **One app-wide database.** A single SQLite database, opened as a GRDB `DatabasePool`, at `~/Library/Application Support/Investment Simulator/`. The app is unsandboxed, and the directory is covered by Time Machine backup.
- **GRDB, as a new dependency.** `GRDB.swift`, pinned to an exact version (7.12.0 when this was written) in `Package.swift`, and used only by `InvestmentSimulatorPersistence`. Core never imports it, so the hexagon stays free of it (ADR-0001). Schema changes are GRDB migrations.
- **No import of old files.** `.invsim` files are not imported. The JSON codec, its DTOs and its migrations are deleted, along with the `DocumentGroup` document type and the exported UTI. This supersedes ADR-0005's rule that every schema version stays readable.
- **Delete only.** Deleting an experiment is permanent. There is no undo and no trash.
- **Fail fast.** If the database can't be opened or migrated, the app shows a clear message naming the path and the underlying error, and doesn't continue with an empty or partial store. It never silently recreates the database.
- **Money stays a decimal string.** Amounts are stored as decimal strings, never as SQLite `REAL` or integer columns, so ADR-0002 holds (`Money` wraps `Decimal`, rounding only at reporting boundaries).
- **One library window.** A single window with a sidebar that holds Research and every experiment. Selecting one shows its detail. This replaces ADR-0011's per-document windows and ADR-0020's `OpenExperiments` and `WindowRaiser`: Research asks the library model to begin a purchase or buy limit order in the chosen experiment directly.
- **Amends ADR-0015.** An experiment's title falls back to "Untitled" when it has no stored name. There is no `fileURL` to fall back to.
- **Amends ADR-0019.** Research is a sidebar entry in the library window, not a separate `Window("Research", id: "research")` scene. Its ports, sections, EDGAR directory and restore behavior are unchanged.
- **Unchanged.** ADR-0001 to ADR-0004 and ADR-0006 to ADR-0009. ADR-0012 to ADR-0014 and ADR-0016 are unchanged apart from where the experiment is stored.

## Options Considered

### Option A: Keep JSON documents

**Pros:**
- Already built and tested, with seven schema versions handled.
- Users own their files and can copy or share them.

**Cons:**
- No library view: the app can't list experiments without scanning folders.
- Keeps the multi-window design, the `OpenExperiments` registry and two AppKit exceptions.
- Every change rewrites the whole file.

### Option B: SwiftData

**Pros:**
- First party, with no new dependency.

**Cons:**
- Already rejected in ADR-0005. Its model types and `ModelContext` would pull persistence into the domain or force a mapping layer anyway.
- Hides the SQL and the stored shape, which matters for money kept as decimal strings.
- A `ModelContext` is tied to its `ModelContainer`'s lifetime, which is easy to get wrong.

### Option C: System SQLite3 C API

**Pros:**
- No dependency.
- Full control of the schema and SQL.

**Cons:**
- We would write and test our own connection pooling, statement handling, migrations and Swift 6 concurrency isolation, which is most of what GRDB provides.
- Manual C interop is easy to get subtly wrong.

### Option D: GRDB

**Pros:**
- Mature SQLite toolkit with `DatabasePool` (concurrent readers with one writer), versioned migrations and Swift concurrency support.
- Plain SQL stays visible, and records are explicit, so the decimal-string money rule is easy to apply.
- Adapter tests can use an in-memory database, so no test touches disk (ADR-0007).

**Cons:**
- A third-party dependency to pin, update and audit.
- Adds a package-resolution step to the build and to CI.

**Chosen:** Option D.

## Consequences

- **Easier:** one window and one composition root for experiments. No registry, raise logic or `NSWindow` access remains. Listing, deleting and querying experiments are ordinary database operations. Schema changes are migrations.
- **Harder:** the app takes on a third-party dependency. Existing `.invsim` files can't be opened, so any saved experiments are lost to the app unless the user keeps the old build. Experiments are no longer files, so sharing one means a future export feature. A corrupt or unwritable database stops the app at launch.
- **Revisit:** an export and import of a single experiment, undo for delete, and sandboxing if the app is ever distributed through the Mac App Store.
- **Follow-up work (PIN-473 children):** the database adapter and schema, the library window, removing `DocumentGroup`, the codec, `OpenExperiments` and `WindowRaiser`, and rewriting the affected parts of `CLAUDE.md`.
