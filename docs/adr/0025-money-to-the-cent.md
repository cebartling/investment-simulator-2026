# ADR-0025: Show Money to the Cent, with the Full Value on Hover

**Status:** Accepted
**Date:** 2026-11-07
**Deciders:** Christopher Bartling

Builds on ADR-0002. ADR-0012's prices are unchanged.

## Context

Equibles sends prices with up to 4 decimals, such as `342.6138` (ADR-0012), and dividends with up to 6. The app showed them that way: every quote and per-share price used `.fractionLength(2 ... 4)`, and Research dividends and statement per-share figures used `2 ... 6`. So a stock card's average price read "$342.6138" and the purchase picker "10 at $342.6138", next to costs, cash and gains shown to the cent. PIN-513 asks for money to show two decimals.

The extra decimals aren't noise in storage. A purchase's cost is its quoted price times its shares, rounded once (ADR-0002), and a dividend can be declared as $0.0975.

## Decision

- **Every amount of money shows to the cent.** That covers quotes, trade and average prices, session prices, the Overview's change, Research dividends and statement per-share figures, as costs, cash and gains already did.
- **Rounding is banker's rounding through `Money.roundedToCents()`** (ADR-0002), so $342.625 shows as $342.62.
- **Hovering an amount that rounding shortened shows it in full:** up to 4 decimals for prices, as they showed before, and up to 6 for dividends and per-share figures. An amount rounding didn't shorten, such as $342.61, has no tooltip. The purchase picker's menu items can't have tooltips, so the picker shows the chosen purchase's price. The Overview's change has none, since it's a difference, not a price.
- **Display only.** Stored prices, costs, proceeds and gains keep every decimal and are computed as before.
- **The rule lives in Presentation,** in `PriceFormatter` (`cents`, `signedCents`, `full`), tested in `PriceFormatterTests`. `ResearchFigureFormatter` uses it for dividends and per-share figures. Views call it, and attach the tooltip with `help(ifPresent:)`.

## Options Considered

### Option A: Keep up to 4 decimals for prices

**Pros:**
- Shows exactly what was quoted.

**Cons:**
- Prices read differently from every other amount, and the extra digits rarely matter to the user.

### Option B: Show cents only

**Pros:**
- Every amount reads alike.

**Cons:**
- A price times its shares can differ from the cost shown beside it, with no way to see why. A $0.0975 dividend reads as $0.10.

### Option C: Show cents, with the full value on hover

**Pros:**
- Every amount reads alike, and the exact value is one hover away.

**Cons:**
- A tooltip to add wherever a price appears.

**Chosen:** Option C.

## Consequences

- **Easier:** reading prices next to costs and gains. Every money format is in one tested type.
- **Harder:** a shown price times the shares can differ from the shown cost, by up to half a cent per share. Hovering the price shows why.
- **Revisit:** whether a new place that shows a price needs the tooltip; `PriceFormatter.full` returns nil when it doesn't.
