# ADR-0019: Research Window, Its Ports, and SEC EDGAR for Tickers

**Status:** Accepted
**Date:** 2026-10-29
**Deciders:** Christopher Bartling

## Context

The Research epic (PIN-412) adds a window for looking up a stock before trading it in an experiment. It shows a quote, a price history chart, a profile, valuation multiples, financial statements, dividends, press releases and SEC filings. The window is app-wide, not tied to an `.invsim` document, and holds several tickers at once.

The PIN-413 spike ([findings](../spikes/PIN-413/README.md)) tested the data sources live:

- **Equibles** (ADR-0012) serves every section, each from its own endpoint. A tab costs about 7 requests when it opens. Statements are one fiscal period per request, so they cost 3–4 more for each statement shown.
- **Equibles has no stock search, and no exchange or CIK.** The CIK is SEC's company ID, which sec.gov filing links need. SEC EDGAR's `company_tickers_exchange.json` gives all three for 10,430 tickers in one keyless download (181 KB gzipped). SEC requires a `User-Agent` that names a contact email, returns `403` without one, and allows at most 10 requests/second.
- **A `404` doesn't always mean an unknown ticker.** `valuation-multiples` answers `404 not_found` both for an unknown ticker and for a company with no computable ratio. Only the message differs, and it can't be relied on (VTI's message names "VB").
- **Coverage is uneven.** Even large companies can have no scraped press releases: AAPL is `attempted`, MSFT `discovered` and VTI `none`; only PLUG of the four sampled is `scraped`. Price history starts in 2020-01. Q4 statements are derived and have no EPS or share-count lines.
- **Finnhub** adds third-party news. But it needs a second key, and its terms are personal use only with no redistribution.

Checked against SwiftUI on macOS 26 with a throwaway app:

- A `Window` scene is single-instance. Opening it again, from the menu or its shortcut, brings the same window forward.
- The `Window` scene adds itself to the **Window** menu, with the shortcut set by `.keyboardShortcut` on the scene. No `commands {}` block is needed. ⇧⌘R clashes with no File or Window menu shortcut.
- A `TabView` draws its tabs as a segmented control in the toolbar, with no close buttons and no way to add a tab. Neither `Tab` nor `TabView` has a close API in the SDK. SwiftUI has no window-tabbing modifier, so native tabbing would need `NSWindow` (ruled out by ADR-0011).

ADR-0004 gives each screen one `@Observable` model, built by a composition root. ADR-0011 keeps document windows from sharing UI state. ADR-0012 names Equibles as the market-data source and keeps the API key in the Keychain.

## Decision

- **One app-wide `Window("Research", id: "research")` scene,** with `.keyboardShortcut("r", modifiers: [.command, .shift])`. It appears in the Window menu as **Research ⇧⌘R**.
- **Open tickers are a sidebar list, not tabs,** in a `NavigationSplitView`.
  - The sidebar lists open tickers in the order they were opened, above a field for opening another.
  - Selecting a ticker shows its sections in the detail pane.
  - A ticker closes from its row's close button, its context menu, or the Delete key.
  - Reordering is out of the first cut. Nothing is restored at launch.
- **Presentation** (`InvestmentSimulatorPresentation`):
  - **`ResearchWindowModel`** owns the open tickers, the selection, and opening a ticker. A typed symbol is validated with a `QuoteProviding` quote first; a search result is opened the same way. Opening a ticker already open selects it.
  - **It is `@State` on `InvestmentSimulatorApp`**, as `SettingsModel` is, so open tickers survive closing and reopening the window during a launch. This is app-wide state, which ADR-0011's no-shared-state rule doesn't cover, because that rule is about document windows.
  - **`ResearchTabModel`** holds one ticker's quote and one state per section: `loading`, `loaded(value)`, `empty(reason)` or `failed(MarketDataError)`. Each section's issue adds its own state and view.
  - Ranges and dates come from an injected `clock: () -> Date`, as in `MainWindowModel`.
- **One Core port per section,** so a test fakes only what it uses and one section's failure stays in that section:
  - `CompanyProfileProviding`: name, sector, industry and market cap, from Equibles' `screener/stocks?tickers=`.
  - `ValuationMultiplesProviding`: P/E, EV/Revenue and EV/EBIT, each with peer median and quartiles.
  - `FinancialStatementProviding`: one statement for one fiscal period per call, as Equibles serves them. The model walks back from the latest period.
  - `DividendProviding`: ex-date, amount per share and currency.
  - `PressReleaseProviding`: rows plus Equibles' coverage status, so "none published" and "not covered" read differently.
  - `FilingProviding`: rows with accession numbers.
  - `SecurityDirectory`: ticker → name, exchange and CIK, plus search by name or symbol, from EDGAR.
  - Price history stays on `DailyPriceProviding`, which gains an interval so 5Y comes back as weekly bars in one request (PIN-416).
  - Ports return Core value types. Money is `Money`, keeping sub-cent fractions until display; ratios and per-share figures are `Decimal`. JSON numbers pass through `Double` once, inside the adapter (ADR-0012).
- **The new ports throw `MarketDataError`,** a new Core enum:
  - `missingAPIKey`, `invalidAPIKey`, `dailyLimitReached` and `unavailable(String)`, as `QuoteError` has.
  - `noData`: a `404` from a per-ticker endpoint after the tab's quote has already validated the ticker. It shows as an empty state, not an error.
  - `missingContactEmail`: an EDGAR request with no contact email saved.

  `QuoteError` doesn't change, and the shell keeps using it for the quote that validates a ticker.
- **A tab loads every section when it opens,** each as a child task of one task group, with cancellation checks (ADR-0003). Financial statements are the exception: each statement and cadence loads when first shown. Closing a ticker cancels its tasks. Nothing polls, and nothing is cached across launches.
- **Sources:**
  - This extends ADR-0012 and doesn't replace it. Equibles serves every data section.
  - SEC EDGAR serves the ticker directory. `company_tickers_exchange.json` is downloaded the first time Research needs it in a launch and kept in memory, never on disk.
  - Every EDGAR request sends `User-Agent: Investment Simulator <contact email>`.
  - Finnhub isn't used.
- **The SEC contact email is the user's, kept in the Keychain:**
  - It's entered in the Settings scene next to the Equibles key, and stored as a generic password: service `com.cebartling.InvestmentSimulator`, account `sec-contact-email`.
  - Code reaches it through a Core port alongside `CredentialStoring`.
  - The adapter reads it on each request, so a newly saved address works without a restart.
  - It never goes in source, a document, `UserDefaults` or a log.
  - Settings checks only that it looks like an email address.
- **Without the contact email, EDGAR is off and Research degrades, not fails:**
  - Tickers open from typed symbols only.
  - The profile shows no exchange.
  - Filing rows link to the Equibles page instead of sec.gov.
  - Each affected section says Settings needs the email.
- **Composition:**
  - `InvestmentSimulatorApp` builds the Equibles and EDGAR adapters once, next to `EquiblesQuoteProvider`.
  - It passes them, with `quotes` and `dailyPrices`, through `ResearchWindow`'s initializer.
  - Nothing goes in `@Environment`.

## Options Considered

### Option A: One `Window` with a sidebar of tickers (chosen)

**Pros:**
- Uses only SwiftUI scene and view API. The system provides the single window, the Window menu item and the shortcut.
- A list holds any number of tickers, and closing one is a plain button or Delete.

**Cons:**
- A sidebar instead of the tabs the epic described, and more width taken by the window.

### Option B: In-window `TabView`

**Pros:**
- Tabs, as groomed, with no custom code.

**Cons:**
- No close button and no "add tab" affordance. The segmented control also crowds the toolbar with a handful of tickers.

### Option C: Native window tabbing (`WindowGroup(for: Ticker.self)`)

**Pros:**
- Real macOS tabs, closing with ⌘W, for free.

**Cons:**
- Each ticker is its own window and composition root, which goes against one Research window.
- Grouping windows into tabs needs `NSWindow` (`tabbingMode`), which ADR-0011 forbids.

### Errors: add `noData` to `QuoteError` instead of a new enum

**Pros:**
- One error type for all market data.

**Cons:**
- Every existing `QuoteError` switch would gain a case that can't happen for a quote. A quote's `404` really is an unknown ticker, and the new ports' `404` really isn't.

### Ticker search: Finnhub `/search`, or typed symbols only

**Pros:**
- Finnhub searches worldwide by name. Typed symbols need no second source.

**Cons:**
- Finnhub needs a second API key under personal-use terms. Typed symbols leave out search and the CIK, and with it the sec.gov links.

### SEC contact: a fixed developer address in source

**Pros:**
- No Settings field, and EDGAR works from first launch.

**Cons:**
- Puts an address in a public repository. Every user's requests would name the developer, not the requester.

## Consequences

- **Easier:**
  - Each section's issue (PIN-416 to PIN-420) adds one port, one adapter, one state and one view, tested with saved fixtures from the spike.
  - A failure or empty result stays inside its section.
- **Harder:**
  - Settings gains a second field, and EDGAR-backed features are off until it's filled in.
  - Two sources with different limits: Equibles' daily count and EDGAR's 10 requests/second. In practice EDGAR sees one request per launch.
  - Two error types for market data.
- **Revisit:**
  - Caching, and Free-plan budgeting, if a 100-request day runs out after a few tabs.
  - Reordering tickers, and restoring them at launch.
  - Third-party news (Finnhub) as its own issue.
  - Whether "Buy in experiment…" (ADR-0020, PIN-421) changes how this window reaches document windows.
