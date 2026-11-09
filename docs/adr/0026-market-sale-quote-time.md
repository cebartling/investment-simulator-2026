# ADR-0026: Record a Market Sale's Quote Time

**Status:** Accepted
**Date:** 2026-11-08
**Deciders:** Christopher Bartling

Amends ADR-0016 and ADR-0024.

## Context

A purchase stores its quote's time (`pricedAt`, the quote's `asOf`). A market sale stores only when the user clicked Sell (`soldAt`, ADR-0016) and the quote's kind. The quote comes from Get Price, so it is older than `soldAt` by however long the sheet stayed open, plus about 15 minutes for a delayed quote. For a live quote, the Sales table showed `soldAt` (ADR-0024), so a sale couldn't be matched to the moment it was priced the way a purchase can. PIN-514 asks for that, ahead of lining trades up with market data.

A sale at a close already stores its session (`SalePriceSource.close(sessionDate:)`), and the table shows that day.

## Decision

- **A market sale also stores its quote's time** (`Sale.quotedAt`, the quote's `asOf`), next to `soldAt`, at a live quote and at a close alike. That matches `Purchase.pricedAt`.
- **`soldAt` still dates the sale (ADR-0016).** It still orders the Sales rows, drives the share check and replays the sale when an experiment is rebuilt. `quotedAt` is only shown.
- **The Sales table shows a sale at a live quote at its quote's time (amends ADR-0024),** in the user's time zone, as the Purchases table shows a purchase. A sale at a close still shows the close's session day.
- **Sales made before this change have no quote time** (`quotedAt` is nil) and keep showing `soldAt`, as they did. Nothing is backfilled.
- **Storage:** the `sale` table gains a nullable `quoted_at REAL` column in migration `v2`, the first after `v1` (ADR-0021). The file is migrated in place, never recreated.
- **The rule lives in Presentation,** in `PriceDateFormatter.tradeTime(ofSaleAt:quotedAt:source:)`, tested in `PriceDateFormatterTests`.

## Options Considered

### Option A: A `quotedAt` field on `Sale`

**Pros:**
- Uniform with `Purchase.pricedAt`: every market sale can carry its quote's time.
- `SalePriceSource` and its stored columns are unchanged.

**Cons:**
- A sale at a close stores a time the table doesn't show.

### Option B: The time inside `SalePriceSource.liveQuote`

**Pros:**
- Only a live quote, the one case that lacks a time, carries one.

**Cons:**
- Every switch over the source changes, and old sales need an optional associated value.

### Option C: Store nothing; show `soldAt`

**Pros:**
- No migration.

**Cons:**
- A sale's price can't be matched to its moment, which lining trades up with market data needs.

**Chosen:** Option A.

## Consequences

- **Easier:** matching a sale's price to the moment it was quoted, as a purchase's already is.
- **Harder:** rows stay in `soldAt` order, so a sale whose sheet stayed open a long time can show an earlier time than the row above it. Old and new live-quote sales read alike but mean different moments.
- **Revisit:** marking trades on the Research chart or a card's Overview (PIN-512 item 3).
