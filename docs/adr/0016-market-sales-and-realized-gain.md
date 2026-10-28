# ADR-0016: Market Sales and Realized Gain

**Status:** Accepted
**Date:** 2026-10-28
**Deciders:** Christopher Bartling

## Context

Until now, shares could be sold only through a sell limit order (ADR-0013, ADR-0014). PIN-409 adds a market sell, the counterpart of buying at a quote: sell shares of one purchase straight away at the market price. It also lists every sale, market or limit fill, with its realized gain.

Questions to settle:

- How a sale is recorded, and how it differs from a filled sell limit order.
- Which shares a sale can take, given that open sell orders reserve shares.
- How realized gain is rounded, so it agrees with the cash.
- How a saved experiment with sales is rebuilt without crediting their proceeds again.

## Decision

- **A market sale is its own Core type, `Sale`,** held in `Experiment.sales`. It records the purchase it sells from, the shares, the price per share as quoted, when it was sold (`soldAt`), and where the price came from. A filled sell limit order stays a `LimitOrder`; it isn't copied into `sales`.
- **A sale's price source is `SalePriceSource`,** with only `liveQuote(delayed:)` and `close(sessionDate:)`. The price comes the same way as for a purchase (ADR-0012): the live quote, or the latest close on `403` or a `stale` quote. A quote's `PriceSource` is mapped to it at the point of sale. `PriceSource.limitOrderFill` has no mapping, so a market sale can never be marked as a limit fill.
- **A sale is dated when the user sells** (`soldAt`), not when its price was quoted. A close can be days old, and the share check has to see the orders as they stand at the sale, after any cancellation since that close. This matches `purchasing(_:at:)`, which takes the time of the purchase apart from its price's date (ADR-0014).
- **A sale takes only available shares**: those of its purchase that no earlier sale or filled sell order took and no open sell order reserves (`availableShares(of:at:)`). To sell reserved shares, cancel the order first. A sale adds its proceeds, price times shares rounded to cents through `Money`, to cash. Like a filled order, a sale's shares are gone for good, whatever date availability is asked about.
- **Realized gain is rounded proceeds minus the rounded cost of the sold shares**: `Money(price × shares).roundedToCents() − Money(purchase.pricePerShare × shares).roundedToCents()`, with banker's rounding (ADR-0002). The proceeds are what the sale adds to cash, and the cost is rounded the way a purchase's cost is, so a sale of a whole purchase gains exactly what cash moved. Each sale rounds its own shares' cost, though, so when one purchase is sold in pieces the gains can total a cent more or less than its cash did: 2 shares bought at $10.005 cost $20.01, but sold one at a time each subtracts $10.00. Allocating cost across a purchase's sales would close that cent at the price of every gain depending on the sales before it. The same rule applies to filled sell limit orders, with the limit price.
- **A filled sell order is dated at its session's close** (`LimitOrder.filledAt`, 4 PM New York), the same time a buy fill's purchase gets. Sales of both kinds then sort by one date.
- **Rebuilding a saved experiment replays sales without touching cash.** The saved balance already includes every sale, so replaying `selling(_:)` would credit the proceeds twice. Instead, sell order placements and sales are replayed together in time order (`placedAt`, `soldAt`), each checked against the shares available then. On a tie, placements go first, then sales, each in saved order. Either order gives the same result: at one instant, an open order and a sale each see the other's shares as taken.
- **ADR-0013's "its shares may have been sold again" now includes market sales.** Fill eligibility is otherwise unchanged: an open order's shares are reserved, so a market sale can't take them.
- **Schema version 7** (ADR-0005) adds `sales`, with money as decimal strings and the price source in its own two-case form. Versions 1–6 read as having no sales.

## Options Considered

### Option A: A separate `Sale` type and price source (chosen)

**Pros:**
- The type can't express a market sale with a limit-fill source.
- Sell limit orders, their fills and their replay are unchanged.

**Cons:**
- The Sales table has to merge two types.

### Option B: Record a market sale as an instantly filled `LimitOrder`

**Pros:**
- One type for every sale.

**Cons:**
- A market sale has no limit, no expiry and no session to fill in, and a quoted price can have fractions of a cent that a limit price can't.

### Option C: Reuse `PriceSource` for sales

**Pros:**
- One fewer enum, and the date formatter needs no overload.

**Cons:**
- A sale could carry `limitOrderFill`, which means nothing for it, and the codec would have to reject it.

### Option D: Round the per-share gain once

**Pros:**
- One rounding step.

**Cons:**
- It can differ from the cash by a cent. Buying at $9.995 and selling 3 at $10.005 gives $0.03, where the ledger moved $0.04.

## Consequences

- **Easier:**
  - Shares can be sold straight away, at the same price a purchase would pay.
  - Realized gain adds up exactly with the cash.
- **Harder:**
  - Rebuilding an experiment has to merge two lists by time.
  - Sales of two types have to be shown together.
- **Revisit:**
  - Ticker-level positions and lot selection (FIFO, LIFO), if selling one purchase at a time gets tedious.
