# ADR-0012: Market Data from Equibles, with the API Key in the Keychain

**Status:** Accepted
**Date:** 2026-10-25
**Deciders:** Christopher Bartling

## Context

PIN-400 lets a user buy an investment: a ticker and a whole number of shares, at a market price, paid from the experiment's cash. The app has had no network access or secrets until now.

The price source is the [Equibles](https://www.equibles.com/docs) REST API (`https://api.equibles.com/v1`, `Authorization: Bearer <key>`):

- `GET /v1/stocks/{ticker}/quote` gives the latest intraday price. Only paid plans get it: Plus is 15 minutes delayed and Pro is real-time. A Free account gets `403`. A quote marked `stale` predates the current session and must not be shown as the current price.
- `GET /v1/prices/latest?tickers=…` gives the latest settled daily close, on every plan. Unknown symbols come back in `notFound`.
- Each account has a daily request limit (Free 100, Plus 10,000, Pro 100,000). Responses with a 4xx or 5xx status don't count toward it.
- Prices are JSON numbers with up to 4 decimal places, such as `316.9961`.

ADR-0001 puts every external system behind a port in Core. ADR-0002 keeps money out of `Double`. ADR-0003 makes ports that do I/O `async`.

## Decision

- **Quotes come through a Core port, `QuoteProviding`,** whose `quote(for:) async throws -> Quote` returns a price and where it came from.
- **A new `InvestmentSimulatorMarketData` target holds the Equibles adapter.** It depends on Core only, and its test target fakes HTTP with an injected `HTTPTransport`, so no test touches the network.
- **The adapter prices a purchase in this order:**
  1. Ask for the live quote.
  2. If the account's plan doesn't include quotes (`403`), or the quote is `stale`, use the latest close and say so.
  3. Turn other failures into a `QuoteError`: no API key, rejected key (`401`), unknown ticker (`404`, or listed in `notFound`), daily limit (`429`), or any other unavailability.
- **Prices leave JSON through `Double` exactly once, in the adapter.** `JSONDecoder` reads every number as `Double`. The adapter converts it with `Decimal(string: String(double))`. `String(Double)` prints the shortest text that reads back as the same `Double`, so a price written with a few decimal places comes back exactly. Nothing outside the adapter sees the `Double`.
- **The API key is stored in the macOS Keychain** as a generic password: service `com.cebartling.InvestmentSimulator`, account `equibles-api-key`. It is entered in a Settings scene. Code reaches it through a Core port, `CredentialStoring`. The adapter reads the key on each request, so a newly saved key works without a restart. The key never goes in a document, `UserDefaults`, the repo, or a log.
- **App-wide services are built once in the `App`**: the credential store and the quote provider. They are passed to each document window through its initializer (ADR-0011).
- **The app is still unsandboxed,** so making network calls needs no entitlement. Sandboxing would need `com.apple.security.network.client`.

## Options Considered

### Option A: Equibles behind a port, quote then close (chosen)

**Pros:**
- Works on every Equibles plan. A Free key still gets a usable, labelled price.
- The domain, presentation and persistence code know nothing about Equibles, so the source can change.
- The adapter's mapping of statuses and JSON is fully tested offline.

**Cons:**
- A second request on Free accounts, which counts against a 100-request daily limit only when the close request succeeds.
- The `Double` conversion is a deliberate exception to ADR-0002 that has to stay inside the adapter.

### Option B: Hand-parse JSON numbers into `Decimal`

**Pros:**
- No `Double` at all.

**Cons:**
- A custom JSON number scanner to write and maintain, for no difference at 4 decimal places.

### Option C: Store the key in `UserDefaults` or an environment variable

**Pros:**
- Simpler code.

**Cons:**
- `UserDefaults` is a plain-text plist. An environment variable isn't seen when the app is opened from Finder.

## Consequences

- **Easier:** further market data (history, more fields) goes in the same adapter behind new port methods. Tests fake both ports in memory.
- **Harder:**
  - The app now depends on a third-party service and its plans.
  - The Keychain and `URLSession` wrappers sit in untested code, the app target or a thin transport, and are checked by hand.
- **Revisit:**
  - Sandboxing (the network-client entitlement and Keychain access groups).
  - Caching quotes if requests come close to the daily limit.
  - Equibles' WebSocket feed if prices need to stream.
