# ADR-0027: Mark Trades on a Stock Card's Price Chart

**Status:** Accepted
**Date:** 2026-11-09
**Deciders:** Christopher Bartling

Amends ADR-0022.

## Context

A stock card lists its trades in the Purchases and Sales tables (ADR-0022), but nothing places them against the market. To see whether a trade was well timed, such as whether a purchase was near a low or a sale came before a rise, you had to compare its date and price with a chart by hand. PIN-515 (item 3 of PIN-512) asks for that.

- Equibles has no intraday history (ADR-0013). Research's chart plots daily closes, or weekly ones for five years (ADR-0019), so a trade can be placed only on its New York session, not its time of day.
- Every trade's session is known. A close or a limit fill has its own. A live quote's is the New York day of its time, the rule `Quote.sessionDate` follows (ADR-0023). A purchase stores that time as `pricedAt`, and a market sale as `quotedAt`, or only `soldAt` before ADR-0026.
- Research is app-wide and shows no experiment, and it never shows together with one (ADR-0021).

## Decision

- **Each stock card gets a Chart pane, after Overview (amends ADR-0022).** It is Research's chart, with a range picker (1M, 6M, 1Y, 5Y) over a line of closes, starting at six months. It has its own pane so its bars load only when it is opened, and Overview, the pane a card opens on, costs no extra request.
- **It marks the experiment's trades of the ticker:** every purchase, including buy limit fills and purchases since sold, every market sale and every filled sell order, each at its price per share as stored. Open, expired and cancelled orders aren't trades, so they aren't marked.
- **A trade sits on its session,** `Purchase.sessionDate` or `Sale.sessionDate` in Core, or a sell fill's `filledOn`.
  - A close or a fill uses its own session. A live quote uses the New York day of `pricedAt`, or of `quotedAt ?? soldAt` for a sale.
  - Both reuse the function behind `Quote.sessionDate`, so there's no new rule.
- **A trade is placed at noon of its session in the user's time zone,** as the closes are, so it sits on its session's point. On weekly bars, each trade sits on its own day between the points; trades aren't grouped by week.
- **Range:** a trade outside the range shown is left out, rather than stretching the axis back to it. A trade made today, before its session settles, shows to the right of the last close.
- **Buys and sells differ by shape and color** (a green triangle and a red diamond), with a legend. Research's chart shows no marks and no legend.
- **Both charts share one model.** `PriceChartModel` holds the range, the chart's state and each range's closes once loaded, moved unchanged out of `ResearchTabModel`. `PriceChartView` draws it.
  - Each card's chart lives in `MainWindowModel` for the app's run (`priceChart(of:)`) and is never saved.
  - `showRange(_:of:)` replaces a range still loading.
- **The rules live in Presentation:** `tradeMarks(of:)`, `chartTrades(of:in:)` and `TradeMark.plot(_:in:within:)`, with tests. The views only render them.
- **Nothing stored changes:** no new stored field and no migration.

## Options Considered

### Option A: A chart on the stock card

**Pros:**
- The card belongs to one experiment, so no experiment has to be chosen.
- The chart sits next to the trades it marks.

**Cons:**
- A second place shows a price chart.
- Each card's chart asks for its bars once per range.

### Option B: Marks on Research's chart

**Pros:**
- One chart serves both.

**Cons:**
- Research shows no experiment, so it would need a way to choose one, such as a picker above the chart.

### Option C: Numbers only, with each trade's price beside the current quote

**Pros:**
- The cheapest option, and it needs no request.

**Cons:**
- It can't show whether a trade came near a low or before a rise.

**Chosen:** Option A, in its own pane rather than inside Overview.

## Consequences

- **Easier:** seeing where the market was at each trade.
- **Harder:**
  - A mark shows no details, such as shares, price or time.
  - Trades in one week can overlap on the five-year chart.
  - A card's chart keeps the ranges it loaded for the app's run, so a chart left open overnight lacks the latest session until the app restarts.
- **Revisit:**
  - Marks on Research's chart, with an experiment picker above it.
  - A trade's details on hover.
  - Lines at the limit prices of open orders.

## Amendment (PIN-519): reloading the chart

A card's chart no longer keeps its ranges for the app's run. It loads them again on a new New York day and on Refresh Prices.

- **A new day:** showing the pane or picking a range asks again, as the Overview's sessions do (`loadLatestSession(of:)`). `MainWindowModel` keeps the day each chart's ranges were asked for on (`chartDays`), and `showRange(_:of:)` forgets them once it changes. On the same day, a range already loaded isn't asked for again.
- **Refresh Prices:** `MainWindowModel.refreshPrices()`, which the footer calls, quotes as before. It also reloads the range of each chart whose pane shows, as Research's Refresh does, and has every other card's chart ask again the next time it shows.
- **Why both:** the day check covers ranges switched to, and other experiments' cards, without a refresh. Refresh gets a session that settled after the chart loaded that day.

Two limits remain:

- A chart left showing overnight keeps the older bars until its pane shows again, a range is picked or Refresh Prices runs. Nothing reloads on a timer.
- A failed reload shows its error and Retry instead of the older bars, as Research's does.

## Amendment (PIN-524): the Overview's month fills 1M

A card's Overview loads the past month of daily bars (`loadLatestSession(of:)`), the same request the chart's 1M range sends. So the chart no longer loads 1M only when it is opened: the Overview's month becomes it.

- **What's kept:** when the Overview's month loads, `MainWindowModel.keepOverviewBars(_:askedFor:of:)` hands it to the card's chart as its 1M range for that New York day, through `PriceChartModel.keep(_:askedFor:as:)`. Picking 1M that day asks for nothing.
- **What isn't:** a month asked for on an earlier day, as when the load ran past midnight, or a load that failed or found an unknown ticker. 1M then asks as before.
- **Reloads are unchanged:** a new day and Refresh Prices forget the kept month as they do every range (PIN-519), so 1M asks again.
- **A 1M load already running** replaces the kept month when it ends, or keeps it if it fails. One asked for on an earlier day, as when it ran past midnight, never replaces it.
