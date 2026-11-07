# ADR-0024: Show When Each Trade Was Priced on Its Stock Card

**Status:** Accepted
**Date:** 2026-11-07
**Deciders:** Christopher Bartling

Amends ADR-0016 and ADR-0022.

## Context

A stock card's Purchases and Sales tables (ADR-0022) showed only the day of each trade, such as "Nov 2, 2026", and so did the sell sheets' purchase picker. Two trades on one day couldn't be told apart, and a trade couldn't be lined up with the price it was made at. PIN-512 asks for that.

Every time is already stored to the second:

- A purchase stores its quote's time (`pricedAt`, the quote's `asOf`). A purchase at a close, or filled from a buy limit order, is dated 4 PM in New York on its session (ADR-0015, ADR-0014).
- A market sale stores when the user sold (`soldAt`, ADR-0016), not its quote's time. A sale at a close can be days after that close.
- A sell fill has only a session day.

## Decision

- **A trade at a live quote shows its day and time in the user's time zone,** such as "Oct 23, 2026 at 10:31 AM", formatted like the Orders table's Placed column. For a purchase, that's its quote's time. For a market sale, it's `soldAt`, when the user clicked Sell. Its quote is older by however long the sheet stayed open after Get Price, plus about 15 minutes for a delayed quote.
- **A trade at a close, or a limit fill, shows its New York session day** with no time, because it has no time of its own.
- **A market sale at a close shows the close's session day, not `soldAt` (amends ADR-0016).** The row reads as the price's day, the same way a purchase at a close does. `soldAt` is still stored, still orders the rows and still drives the share check.
- **The purchase picker follows the same rule (amends ADR-0022),** since it's where two purchases on one day most need telling apart.
- **The rule lives in Presentation,** as `PriceDateFormatter.tradeTime(of:source:)` for purchases and `tradeTime(ofSaleAt:source:)` for market sales, tested in `PriceDateFormatterTests`. The views only call it.
- **Nothing stored changes:** no Core field and no migration.

## Options Considered

### Option A: Show `soldAt` for every market sale

**Pros:**
- The table shows exactly when the user sold.

**Cons:**
- A sale at a close reads as a day whose prices it wasn't made at, unlike a purchase at a close.

### Option B: Show `soldAt`, plus a note naming the close

**Pros:**
- Shows both when the user sold and where the price came from.

**Cons:**
- Makes the Date column wider for an uncommon case.

### Option C: Show a sale at a close by its session day

**Pros:**
- Every trade at a close reads the same way, as the price's day.

**Cons:**
- The row no longer shows when the user sold.

**Chosen:** Option C.

## Consequences

- **Easier:** telling apart two trades on one day, and seeing what moment a trade's price came from.
- **Harder:** rows stay in `soldAt` order, so a sale at a close can show an earlier day than the row above it.
- **Revisit:** whether trades outside market hours need a label. Storing a sale's quote time (PIN-512 item 2), and marking trades on the Research chart or a card's Overview (item 3), which can match trades only to a session while Equibles has only daily bars.
