# ADR-0014: Buy Limit Orders, Reserved Cash and Order Cancellation

**Status:** Accepted
**Date:** 2026-10-26
**Deciders:** Christopher Bartling

## Context

PIN-401 and PIN-402 added sell limit orders on purchases and fill them from daily bars (ADR-0013). PIN-404 adds buy limit orders: buy a number of shares of a ticker once its price drops to a limit. Once buy orders hold cash, a user also needs a way to give it back, so PIN-404 adds cancelling an open order of either kind.

Questions to settle:

- Whether an open buy order holds its cash, or cash is checked only when it fills.
- What price a buy order fills at, and which sessions can fill it.
- What a fill becomes in the experiment.
- How a cancellation is recorded, so a saved file still opens and replays the same way.

## Decision

- **A buy limit order is its own Core type, `BuyLimitOrder`,** held in `Experiment.buyLimitOrders`. `LimitOrder` stays the sell order. A shared type would need a side and an optional purchase or ticker, and every sell rule, the codec and the table would have to check them.
- **An open buy order reserves its cost,** the limit price times the shares rounded to cents through `Money`. `Experiment.availableCash(at:)` is the balance minus the cost of the buy orders open then. Placing a buy order and buying at a quote both spend only available cash. Cash never goes negative when an order fills, and fills don't depend on the order they are checked in.
- **A buy limit order fills in the first eligible session whose low is at or below its limit price, at exactly the limit price.** This mirrors ADR-0013. Only orders open when the check runs can fill. Eligible sessions come after the placement session and before today in New York. An order that expired or was cancelled before anyone checked never fills.
- **A fill becomes a `Purchase`** of the order's ticker and shares at the limit price. Its source is `PriceSource.limitOrderFill(sessionDate:)`, and it is priced at 4 PM New York on that session, the close. **The purchase takes the order's id.** Core makes no ids of its own: it has no randomness (ADR-0007). The shared id also links the purchase to its order without another field. Sell limit orders can then be placed on it like any purchase.
- **A cancellation is stored as the time it happened** (`cancelledAt`) on both order types. An order is open while it is unfilled, before its expiry, and before its cancellation. Rebuilding a saved experiment checks every placement at its own time (ADR-0013), so a cancelled order's shares count as reserved before the cancellation and as free after it. Only an open order can be cancelled. A cancelled order stays in the experiment and never fills.
- **Schema version 5** (ADR-0005) adds `buyLimitOrders`, `cancelledAt` on both order types, and the `limitOrderFill` price source. Versions 1–4 read as having no buy orders and no cancellations.
- **A saved experiment is checked on open.** Each filled buy order must have its purchase, a `limitOrderFill` from the same session. Each unfilled one must have none. Reserved cash isn't checked against the balance, because the balance stored is the one after every fill and purchase, and there's no record of what it was when each order was placed.

## Options Considered

### Option A: Reserve cash, fill at the limit, fill into a purchase (chosen)

**Pros:**
- Matches sell orders, which reserve shares.
- A fill can never overdraw cash, so replay needs no cash check.
- Filled shares are an ordinary purchase: they show in Purchases and can be sold with a limit order.

**Cons:**
- Cash tied up in an open order can't be used until the order fills, expires or is cancelled.

### Option B: Check cash only when an order fills

**Pros:**
- Cash stays free while an order is open.

**Cons:**
- A fill could find too little cash, so the result of a check would depend on the order of the fills and the purchases in between.

### Option C: Fill at `min(limit, open)`

**Pros:**
- Matches how a gap-down open fills a real buy limit order.

**Cons:**
- Rejected for the same reason as ADR-0013's Option D: one simple rule, fill at the limit.

### Option D: Delete cancelled orders

**Pros:**
- Nothing to store.

**Cons:**
- Rebuilding a saved experiment checks each sell order's shares at its placement time. Deleting an order changes that history and loses what the user did.

## Consequences

- **Easier:**
  - Buy and sell fills replay from the same daily bars in one check.
  - A cancelled order frees its cash or shares straight away.
- **Harder:**
  - Two order types with similar rules (expiry, open, cancel) to keep in step.
  - The id of a purchase made by a fill is chosen by its order, not by the Buy sheet.
  - Opening a file can't check that its open buy orders fit the balance, because the saved balance comes after every fill. In an edited file where one doesn't, Check Orders fails with insufficient cash and fills nothing, sell orders included.
- **Revisit:**
  - Editing an order instead of cancelling and placing a new one.
  - Filling at a gap-down open, if the conservative fill misleads.
