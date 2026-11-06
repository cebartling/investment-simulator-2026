# ADR-0023: Show a Stock's Quote, Change and Unrealized Gain on Its Card's Overview

**Status:** Accepted
**Date:** 2026-11-06
**Deciders:** Christopher Bartling

Amends ADR-0012, ADR-0015 and ADR-0022.

## Context

ADR-0022 gave each stock card an Overview showing the open, high, low and close of the ticker's latest settled daily bar. During trading, that's yesterday's numbers. PIN-511 asks for the live quote instead.

The account is on Equibles Plus: quotes are 15 minutes delayed, with 10,000 requests a day. Equibles' live quote has a price, bid, ask, `asOf`, `sessionDate`, `stale` and `delayed`, but no open, high, low or previous close. Equibles has no intraday history either (ADR-0013). So the Overview can't show today's open, high and low. It can show the current price, how far it is from the previous close, and what the shares held are worth.

## Decision

- **The quote on top, the last session below.** The Overview shows:
  - the price, labeled as everywhere else (`PriceDateFormatter.label(for:)`): "15-minute delayed quote, …", "Live quote, …" or "Close on …";
  - its change since the previous close, in dollars and percent, green when up and red when down;
  - with shares held, their market value and unrealized gain;
  - the latest settled session, as ADR-0022 shows it.
- **A quote's session (amends ADR-0012).** `Quote.sessionDate` is a close's own session, else the New York day of the quote's `asOf`. A quote taken at 8 PM in New York, past midnight UTC, is that New York day's. The adapter already answers a stale quote with the latest close, so a live quote is always in the current session. The adapter and `Quote`'s stored fields are unchanged.
- **The change.** It's the quote's price minus the close of the latest session *before the quote's session* (`Quote.change(since:)`, a `PriceChange`, per share and unrounded). During and after trading that's the day before, whether or not today's bar has posted. A close of Nov 5 compares with Nov 4. The Overview keeps the month's bars for it (`RecentSessions`), not just the latest. The change shows only once they load. It's hidden while they load, when they fail, or when no earlier session falls in the past month.
- **The unrealized gain.** The market value is the price times the shares held, rounded to cents (`Experiment.marketValue(of:at:)`). The cost rounds each purchase to cents, as `investedCost` does (`investedCost(of:)`), so the cards' costs add up to the header's Invested exactly. Each card rounds its market value on its own, while the header rounds its total once, so the cards' market values can differ from the header's by up to half a cent per stock. The gain is a `Gain`, whose base is now the cost or the starting cash, so a cost that rounds to $0.00 shows "—" for its percent.
- **The quotes are the header's (amends ADR-0015).** The Overview reads `HoldingsPricesModel`'s last good quote. A held stock's Overview costs no extra request, and the card and the header always agree. A card with no shares, fully sold or with only orders, asks for its ticker with `priceOnDemand(_:)` when its Overview first shows, and again if its last shares go while it shows.
- **Refresh Prices covers those tickers too (amends ADR-0015).** It requotes every held ticker and every ticker asked for, whether its quote answered or failed (`refreshPrices(holding:)`). It's enabled whenever there is any such ticker, even with nothing held (`canRefresh(holding:)`), so a card whose first quote failed can always be retried. Total Value and "Prices as of" still count held tickers only. Nothing polls.
- **Concurrency (amends ADR-0015).** Each run still quotes at most four tickers at once, but runs don't share the limit. New holdings, an on-demand quote and a refresh can overlap and have more than four quotes out. That's acceptable on Plus, with an experiment's few stocks.
- **Failures.** While the first quote loads, the price shows "—" with a spinner. A failed first quote shows its reason, the same text as the footer, and the last session still shows. A failed refresh keeps the last good quote and shows no error, as the footer does.
- **The rules live in Presentation.** `MainWindowModel.overview(of:)` returns a `StockOverview` with the price, the change, the holding and the last session. Its tests use the in-memory fakes. The view only renders it, since the app target has no tests.
- **Amends ADR-0022.** The Overview is no longer the latest settled session alone.

## Options Considered

### Option A: Fetch a quote for each open card

**Pros:**
- Each card stands alone.

**Cons:**
- A held stock costs a second request for a quote the header already has.
- The card and the header can show different prices.

### Option B: Reuse the header's quotes, and ask for a card's ticker only when it holds no shares

**Pros:**
- No extra request for a held stock, and the card and header always agree.
- One place keeps the last good quote and the failure of every ticker.

**Cons:**
- `HoldingsPricesModel` is no longer only for the header, and Refresh Prices covers more than the holdings.

### Option C: Show today's open, high and low

**Pros:**
- The figures PIN-510's Overview already lays out, for today.

**Cons:**
- Equibles' quote doesn't have them. They'd need polling, which ADR-0015 rules out, or Equibles' `/stream`, a new transport.

**Chosen:** Option B.

## Consequences

- **Easier:** seeing where a stock stands now, and what its shares have gained, without leaving its card.
- **Harder:** what Refresh Prices quotes now depends on which cards have asked, not only on the holdings.
- **Revisit:** today's open, high and low, and bid and ask, if Equibles' `/stream` is adopted. A limit shared across quote runs, if request volume grows.
