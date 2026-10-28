# ADR-0015: Experiment Name, Notes and Created Date, and Quoting Holdings on Open

**Status:** Accepted
**Date:** 2026-10-28
**Deciders:** Christopher Bartling

## Context

PIN-408 replaces the Experiment section's cash-only header with a header that names the experiment and shows five tiles: Total Value, Gain/Loss, Cash, Available and Invested. Two parts of that need decisions.

- **Identity.** A title, a note and a "Started <date> with <cash>" line need data the experiment doesn't store: a name, notes and a created date. Older files have none of these.
- **Market value.** Total Value and Gain/Loss need a price for every held ticker. Until now the app fetched prices only when the user asked: Get Price on the Buy sheet, and Check Orders, which ADR-0013 keeps manual.

Questions to settle:

- Where the name, notes and created date live, and what an older file gets.
- Where starting cash comes from.
- When holdings are quoted, and what the tiles show without prices.
- Whether editing the details can be undone.

## Decision

- **`Experiment` gains `name`, `notes` and `createdAt`, all optional.** The header's title is the name, else the document's file name, else "Untitled". The file name comes from the `DocumentGroup`'s `fileURL`, read in the scene's body, so the title follows Save As. Renaming the file doesn't change a name the user set.
- **Schema version 6** (ADR-0005) adds the three fields, each left out of the file when unset. Versions 1–5 read with no name or notes, and with `createdAt` set to the earliest purchase `pricedAt` or order `placedAt`, sell or buy. With neither, it stays nil and the subtitle shows only the starting cash.
- **A new experiment's `createdAt` comes from the window's injected clock,** through `NewExperimentModel`. The New Experiment sheet doesn't ask for a name or notes; Edit Details sets them.
- **Starting cash is derived, not stored:** the cash balance plus every purchase's cost, less every sell fill's proceeds. A buy fill is one of the purchases, and open or cancelled orders moved no cash, so this holds for every experiment schema 5 can describe.
- **Invested is the cost of the shares still held.** For each purchase it is the held shares times its price, rounded to cents, and those are summed, so a fully held purchase matches its Cost column. Held shares leave out only filled sells. Unlike `availableShares(of:at:)`, they still count shares an open order reserves.
- **Holdings are quoted when the window opens, again when the user clicks Refresh Prices, and for each newly held ticker** after a buy or a fill. Nothing polls. Each held ticker is quoted once through `QuoteProviding` (ADR-0012), at most four at a time, in structured concurrency that stops when the holdings change (ADR-0003). This differs from Check Orders, which stays manual (ADR-0013): a header without prices shows no value at all, while an unchecked order only waits.
- **Total Value and Gain/Loss need every held ticker priced.** Until then they show "—", with "Getting prices…" or the failed quote's message, such as the missing API key. Each ticker keeps its last good quote, so a failed refresh falls back to it. "Prices as of" shows the earliest quote time among the held tickers. An experiment with no holdings needs no quotes. Gain/Loss shows its percent as "—" when the starting cash is $0.
- **Editing the details can be undone.** In the bundled app, every write to the document's `experiment` registers an undo with the document. That covers purchases, orders and Edit Details, so Edit Details adds no undo code of its own (checked 2026-10-28). Saving details that didn't change writes nothing, so the document isn't marked edited.

## Options Considered

### Option A: Optional fields in the experiment, derived figures, quotes on open (chosen)

**Pros:**
- One document carries everything the header shows; nothing is kept beside it.
- Starting cash and Invested can't drift from the purchases and fills they come from.
- The header has its value as soon as the window opens.

**Cons:**
- Each window open costs about two requests per held ticker: a live quote, then the latest close on `403` or a stale quote. On the Free plan's 100 requests a day, a few opens of an experiment with many tickers adds up.
- A backfilled `createdAt` can come before the experiment was really created. A purchase at a session's close carries that session's 4 PM time, which can be earlier than the day the user made it.

### Option B: Store the starting cash

**Pros:**
- No derivation to get wrong.

**Cons:**
- Older files don't have it, so it would be backfilled by the same derivation anyway, and stored figures can disagree with the history.

### Option C: Quote only on Refresh Prices

**Pros:**
- No requests the user didn't ask for, matching Check Orders.

**Cons:**
- Every window opens with Total Value and Gain/Loss at "—", so the header's main figures would usually be missing.

### Option D: Poll prices while the window is open

**Pros:**
- The value stays current.

**Cons:**
- Burns the daily request budget, and the daily bars that drive the rest of the app don't change during the day.

## Consequences

- **Easier:**
  - The header shows an experiment's value and performance at a glance.
  - Older files open with a sensible created date and no migration step for the user.
- **Harder:**
  - Opening windows spends API requests.
  - The header is taller. `ContentView`'s minimum height rises from 480 to 640 points so both tables keep a few rows; the minimum width stays 640.
  - PIN-409 (market sells) must extend `startingCash`, `heldShares` and `investedCost` for sales, and moves to schema version 7.
- **Revisit:**
  - Caching quotes across windows, if the request budget runs short.
  - Showing a quote as stale when a refresh fell back to its last good price.
