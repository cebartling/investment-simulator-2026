# ADR-0013: Fill Limit Orders from Daily Bars, at the Limit Price

**Status:** Accepted
**Date:** 2026-10-25
**Deciders:** Christopher Bartling

## Context

PIN-401 lets a user place sell limit orders on purchases, but nothing fills them. PIN-402 asks for a day's price updates for a ticker, a replay of them, and fills for any limit order they trigger.

What Equibles offers (ADR-0012), checked against the docs and a probe with a Plus key on 2026-10-25:

- **No historical intraday prices on any plan.** The docs say `/quotes` and `/stream` "provide current intraday snapshots or updates, not historical intraday candles; use the daily-price endpoint for stored OHLCV history."
- **Daily bars on every plan.** `GET /v1/stocks/{ticker}/prices?startDate=…&endDate=…&limit=500` returns `date`, `open`, `high`, `low`, `close`, `adjustedClose` and `volume`, newest first, paged by `offset` while `meta.hasMore` is true.
- **No live stream.** The documented `/v1/stream` WebSocket answered `404` "Unknown endpoint". The docs also cap it at 5 tickers per account. ADR-0012 lists this feed under Revisit.
- **When a session's bar appears is unknown on Plus.** On Free, it's 4 hours after the close.

A daily bar shows that a price was reached during a session, but not when.

## Decision

- **Fills come from daily bars,** through a Core port, `DailyPriceProviding`, which the Equibles adapter implements.
- **A sell limit order fills in the first eligible session whose high is at or above its limit price.**
- **It fills at exactly the limit price,** even when the session opens above it. Cash gains the limit price times the shares, rounded to cents through `Money`.
- **A session is eligible when it is after the session the order was placed in, before the date the order expires, and before today in New York.** The placement session is skipped because its high may have come before the order was placed. The expiry date is skipped because its high may have come after the order expired. Today is skipped because its bar isn't settled.
- **The user starts a check** with a Check Orders button. It makes one request per ticker with an unfilled order that an eligible session could fill. Nothing checks automatically.
- **Orders that expired unfilled are still checked** for the sessions before they expired, so a fill missed while the app was closed is found later.
- **A fill is stored as the session it happened in** (`filledOn`, `yyyy-MM-dd`) in schema version 4 (ADR-0005). No price is stored, since a fill is always at the limit price.
- **The replay rule lives in Core,** as `Experiment.fillingLimitOrders(from:at:)` and `Experiment.sessionsToReplay(at:)`, and is tested without I/O.

## Options Considered

### Option A: Daily bars, filling at the limit, skipping the placement session (chosen)

**Pros:**
- Works on every Equibles plan and can replay any past session, whether or not the app was running then.
- Conservative: the order never fills on a price that may have come before it was placed or after it expired, and never fills above its limit.

**Cons:**
- Coarse. An order placed during a session whose later high reaches the limit waits for the next session.
- Filling at the limit understates proceeds when a session opens above it.

### Option B: Record our own tape of intraday quotes

Poll `/v1/quotes`, or the `/v1/stream` WebSocket once it is served, while the app is open, store the readings, and replay them.

**Pros:**
- Granular fills within a session.

**Cons:**
- Covers only the time the app was running.
- Needs a paid plan, counts against the daily request limit or the 5-ticker stream cap, and adds storage.

### Option C: Another provider with intraday history

**Pros:**
- Granular history for any past session.

**Cons:**
- A second provider, account and secret, with its own adapter, for an experiment.

### Option D: Fill at `max(limit, open)`

**Pros:**
- Matches how a gap-up open would fill a real sell limit order.

**Cons:**
- Rejected in favor of the simpler rule that an order fills at its limit price.

## Consequences

- **Easier:**
  - Fills replay deterministically from bars, so tests cover every rule with in-memory fakes.
  - A finer source later only needs a new adapter or port. The fill rule and the file format stay.
- **Harder:**
  - Results are coarser and more conservative than a real market would give.
- **Revisit:**
  - Intraday fills if Equibles serves the stream or intraday history.
  - Counting the placement session when an order was placed before that session opened.
  - When Plus publishes a session's bar, if fills should come sooner.
