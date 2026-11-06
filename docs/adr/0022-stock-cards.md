# ADR-0022: Show an Experiment's Stocks as Cards, Selling from a Chosen Purchase

**Status:** Accepted
**Date:** 2026-11-06
**Deciders:** Christopher Bartling

Amends ADR-0015 and ADR-0016. ADR-0013 and ADR-0014 are unchanged.

## Context

An experiment showed three tables below its header: every purchase, every sale (market sales and sell fills, ADR-0016), and every limit order. Each row named its ticker, so an experiment holding several stocks mixed them all together, and nothing showed how many shares of a stock were held or at what average price. Market Sell and Sell Limit acted on the purchase selected in the Purchases table, so selling meant finding the right row first.

PIN-510 asks for one card per stock instead: its ticker, company name, shares held and average price, opening onto panes for its purchases, sales and orders, with each action button in the pane it belongs to. ADR-0016 had already named ticker-level positions and lot selection as something to revisit.

## Decision

- **A card per stock, by symbol.** A ticker gets a card if the experiment bought it, or if it has an order row showing. A fully sold stock keeps its card, with 0 shares and "—" for its average, so its sales and orders stay reachable. A ticker whose only orders expired or were cancelled, and never filled, has a card only while Expired & Cancelled is on (`MainWindowModel.stockCards(at:)`).
- **Held shares and average price come from Core, unstored.** `Experiment.heldShares(of:)` for a ticker adds up its purchases' held shares, as the header's figures count them. `averagePrice(of:)` weighs each purchase's price by its held shares and stays unrounded, like a quoted price. Held cost over held shares would round each purchase to cents first, so a single purchase's average would differ from its own price.
- **Panes.** An open card shows Overview, Purchases, Sales and Orders, chosen with a segmented picker and kept per ticker while the app runs. A `TabView` sizes poorly inside a scroll view. Purchases holds Market Buy for that ticker, Sales holds Market Sell, and Orders holds Buy Limit, Sell Limit and Cancel Order.
- **Overview is the latest settled session, for now.** The open, high, low and close of the ticker's latest daily bar in the past month, through `DailyPriceProviding`, labeled with its session's day. A live quote is to replace it (PIN-511).
- **Selling from a chosen purchase.** Market Sell and Sell Limit open for a ticker and offer each of its purchases still held (`SellablePurchase`), starting on the one the user acted on, else the first with free shares. Shares are still sold per purchase, not pooled by first-in-first-out or any other rule, so ADR-0016's realized gain is unchanged. The picker replaces each sheet's purchase price row, so neither sheet grows (PIN-405).
- **Above the cards.** Market Buy and Buy Limit for a ticker not yet held, Check Orders with its message (ADR-0013), and the Expired & Cancelled toggle. The toggle is here, not on a card, because a card shown only for expired orders needs it to come back.
- **Company names.** `MainWindowModel` takes a `CompanyProfileProviding`, the same Equibles adapter Research uses (ADR-0019), and loads a ticker's name once, as its card appears. A ticker with no profile isn't asked again. Any other failure is asked again the next time the card appears, so a newly saved API key works without a relaunch.
- **Layout.** The cards sit in a plain `VStack` in a `ScrollView`. An experiment holds few stocks, and a lazy stack would drop each card's table selection as it scrolls away. A table inside a scroll view has no height of its own, so each gets room for up to six rows, then scrolls.
- **Amends ADR-0015.** The library window's 640-point minimum height now leaves room for the stock cards below the header, not for two tables.
- **Amends ADR-0016.** The Sales table is per stock, inside its card, and Market Sell chooses its purchase in the sheet.

## Options Considered

### Option A: Keep the tables, grouped or filtered by ticker

**Pros:**
- Little new UI. Every row stays visible at once.

**Cons:**
- Still no held shares or average price per stock.
- Selling still depends on a selected row.

### Option B: An outline list of tickers with disclosure rows

**Pros:**
- Native `List` and `DisclosureGroup` behavior.

**Cons:**
- Purchases, sales and orders have different columns, which nested rows can't show as tables.

### Option C: A card per stock, with panes

**Pros:**
- Each stock's figures at a glance, and its history one click away.
- Each action sits with what it changes.

**Cons:**
- Tables inside a scroll view need set heights.
- Orders for one stock are split from the others, so seeing every open order means opening each card.

**Chosen:** Option C.

## Consequences

- **Easier:** reading what an experiment holds, per stock. Selling without hunting for a row.
- **Harder:** comparing orders across stocks, which now live in separate cards. Each card's tables have set heights, so a stock with many purchases scrolls inside its card.
- **Revisit:** the Overview once the live quote lands (PIN-511), and lot rules such as first-in-first-out if choosing a purchase gets tedious.
