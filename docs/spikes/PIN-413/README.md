# PIN-413 spike: Equibles, SEC EDGAR and Finnhub for Research

Findings for the Research epic (PIN-412), from live calls made on 2026-10-29 with the Equibles **Plus** plan (10,000 requests/day), SEC EDGAR, and a Finnhub free-tier key. No production code. The JSON beside this file is real responses, trimmed to a few rows and checked for API keys and personal data, for adapter tests to copy into inline fixtures as the existing tests do.

## Recommendation

| Section | Source | Requests per tab | Notes |
|---|---|---|---|
| Ticker search | EDGAR `company_tickers_exchange.json` | 1 per launch (181 KB gzipped) | No key. Name, ticker, CIK, exchange. Has operating companies and many ETFs (SPY), not mutual-fund-style series (VTI). Typed symbols stay the fallback. |
| Quote | Equibles (unchanged) | 1 | |
| Price chart | Equibles `prices` | 1 per range | `interval=weekly` makes 5Y one request, not 3. History starts 2020-01. |
| Profile | Equibles `screener/stocks?tickers=` + EDGAR list | 1 | Sector, industry, name, market cap from the screener; exchange from the EDGAR list already in memory. |
| Valuation multiples | Equibles `valuation-multiples` | 1 | |
| Statements | Equibles `financial-statements` | 4 (quarterly) or 3 (annual) per statement, on demand | |
| Dividends | Equibles `dividends` | 1 | |
| Press releases | Equibles `ir-news` | 1 | Coverage is thin even for large caps. |
| SEC filings | Equibles `filings?limit=50`, filtered client-side | 1 | sec.gov links need the CIK from the EDGAR list. |
| Third-party news | Not in the first cut | — | Finnhub works, but see below. |

A tab costs **7 requests** when it opens (quote, chart, screener, multiples, dividends, IR news, filings), plus 3–4 for the first statement shown. Showing every statement at both cadences adds 21. The epic's "about 7" holds.

Epic decisions this changes:

- **"Equibles only"** becomes Equibles plus SEC EDGAR, for the ticker list, exchange and CIK. That needs ADR-0019 (or its own ADR) to amend ADR-0012.
- **"No third-party news"** stays. Finnhub would reverse it, but it costs a second key and personal-use terms for a section the epic marked out of scope. Worth its own issue later.
- **Sector and exchange (PIN-417):** both available, from the screener and EDGAR.
- **sec.gov links (PIN-420):** possible with EDGAR's CIK, not from Equibles alone.
- **Statement cost (PIN-418):** as groomed; `financial-facts` is not cheaper for a full table.
- **Ticker search (PIN-422):** EDGAR's list, not an Equibles endpoint.
- **Price history (PIN-416):** one request per range, and a 10Y range would not work.

## Equibles

Docs: <https://equibles.com/docs>, also as one Markdown file at <https://equibles.com/docs/llms-full.txt>. There is no OpenAPI file.

**Limits.** Free 100, Plus 10,000, Pro 100,000 requests/day, shared with MCP, resetting at 00:00 UTC. Responses carry `X-RateLimit-Limit`, `-Remaining` and `-Reset`. **4xx and 5xx responses do not count.** Over the limit is `429`. The only plan gates relevant here are live/intraday quotes (`403`) and Free's 4-hour delay on the newest daily bar. Everything else below works on Free.

**Errors.** Every error is `{"error": {"code", "message", "status"}}`. An unknown ticker is `404` `not_found` with `"Stock 'ZZZZQ' not found."` on every per-ticker endpoint (`valuation-multiples`, `financial-statements`, `dividends`, `ir-news`, `filings`).

### Search — none

`GET /v1/stocks?query=` is `404 Unknown endpoint` (`search-stocks.json`). `/v1/funds?query=` and `/v1/etfs?query=` search funds only. The screener has no name filter.

### Profile — `GET /v1/screener/stocks?tickers=AAPL`

One row per ticker with `name`, `sector`, `industry`, `marketCap`, `price`, `currency`, `market` and dozens of screener fields (`screener-AAPL.json`). No exchange. An unknown ticker is `200` with `"data": []` and `"notFound": ["ZZZZQ"]`. The envelope is `totalCount`/`count`/`page`/`totalPages`, not `data`/`meta`.

### Valuation multiples — `GET /v1/stocks/{ticker}/valuation-multiples`

As documented (`valuation-AAPL.json`): `companyName`, `industry`, `marketCap` (`5024265535488.0`, trillion-scale), `peRatio`, `evToRevenue`, `evToEbit`, their TTM inputs, and `industryContext` with `…Median`/`…P25`/`…P75` and per-ratio peer counts. Medians are `null` below three peers. AAPL's `peMedian` and `evToEbitMedian` are `null` (two peers each).

**"No ratio" and "unknown ticker" share `404 not_found`**; only the message differs (`valuation-VTI.json` vs `valuation-ZZZZQ.json`). The VTI message even names another ticker ("VB has no computable valuation multiple"), so the text can't be matched reliably. Because the tab validates the ticker with a quote first, the adapter should treat a `404` here as "no data". The error type is ADR-0019's call.

### Statements — `GET /v1/stocks/{ticker}/financial-statements/{income|balance|cashflow}?year=&period=`

One period per request, as groomed. With no query it returns the latest period (`fiscalYear: 2026`, `fiscalPeriod: "Q3"` for AAPL). Line counts: income 18, balance 20, cash flow 11.

- Line fields: `lineItem`, `value`, `unit`, `basis` (`reported`/`derived`), `periodStart`, `periodEnd`, `form`, `filedDate`, `accessionNumber`, `documentId`, and `splitBasis` on per-share and share-count lines.
- **Units are `USD`, `USD/shares` and `shares`** (not "per-share").
- **Q4 is derived** (FY minus nine months). AAPL FY2025 Q4 has 14 lines, all `basis: "derived"`, **with no EPS or share-count lines**; the table needs "—" there (`income-AAPL-Q4.json`).
- Cash-flow quarters are mostly `derived` too.
- A missing period is `404` whose message lists the periods that exist ("Reported periods include: FY2026 Q3, FY2026 Q2, …"). Don't parse it; walk back from the latest `fiscalYear`/`fiscalPeriod`.

`GET /v1/stocks/{ticker}/financial-facts/{concept}` returns one concept's whole history in one request (AAPL revenue: 67 quarters from FY2008, 19 years), with `quarterly` and `annual` arrays, oldest first. An unknown concept is `400` listing every alias (`facts-AAPL-bad.json`). It costs one request per line, so a full 18-line income table is cheaper with `financial-statements` (4 requests). It would only win for a slim table of a few lines across many periods.

### Dividends — `GET /v1/stocks/{ticker}/dividends`

Rows are exactly `{exDate, amountPerShare, currency}` (`dividends-AAPL.json`), newest first, with `{limit, offset, count, hasMore}`. No pay date, no yield. The docs confirm future, declared ex-dates can appear. A non-payer (AMZN) is `200` with `"data": []`; an unknown ticker is `404`.

### Press releases — `GET /v1/stocks/{ticker}/ir-news`

`{coverage: {status, lastScrapedAt}, data: [{publishedAt, title, url, summary}], meta}`. All four coverage statuses showed up:

| Ticker | `coverage.status` | Rows |
|---|---|---|
| PLUG | `scraped` | 5 of many |
| AAPL | `attempted` | 0 |
| MSFT | `discovered` (`lastScrapedAt: null`) | 0 |
| VTI | `none` | 0 |

Coverage is worse than the epic assumed: Apple and Microsoft have none. `url` links straight to the company's IR site. `summary` was `null` in every row.

### Filings — `GET /v1/stocks/{ticker}/filings`

Rows: `id`, `ticker`, `companyName`, `documentType` (`TenK`, `TenQ`, `EightK`, …), `documentTypeName` (`10-K`), `filedDate`, `reportingForDate`, `itemNumbers`, `accessionNumber`, `url` (an equibles.com page), and more.

- `documentType` takes one value; a list is `400` naming every valid value (`filings-AAPL-multi.json`).
- Unfiltered, the list mixes in earnings-call transcripts (`accessionNumber: null`) and proxies. AAPL's latest 50 rows reach back to 2024-05 and hold 2 10-Ks, 8 10-Qs and 23 8-Ks. **One `limit=50` request filtered client-side** covers the section; three per-form requests would cost three.
- **The accession number's prefix is not always the company's CIK.** Of AAPL's 39 accessions, 20 start `0000320193` (Apple) and 19 start with filing agents' IDs. A sec.gov link (`https://www.sec.gov/Archives/edgar/data/{CIK}/{accession without dashes}/`, checked for AAPL's 10-K) needs the CIK from EDGAR.

### Prices — `GET /v1/stocks/{ticker}/prices`

- **History starts 2020-01** (AAPL monthly since 2000 returns 82 bars, the oldest `2020-01-31`; before 2000 is empty). 5Y works; 10Y would not.
- `interval=weekly|monthly` rolls bars up, each with `periodStart` and `partial`. **5Y weekly is 262 bars in one request**; 1Y daily is 252. So every range is one request, not 3 for 5Y. Weekly bars are dated by their last session, so the chart can use them as they are.
- The quote response has no `source` field (the current test fixture includes `"source": "Rest"`); the adapter doesn't read it.

## SEC EDGAR

Free, no key. Rules at <https://www.sec.gov/search-filings/edgar-search-assistance/accessing-edgar-data>:

- **Declare a User-Agent** with a name and contact email (`Sample Company Name AdminContact@<domain>.com`). Without one, `data.sec.gov` returns `403` (checked). The app would have to send one; whose contact it names is ADR-0019's decision.
- **At most 10 requests/second**, and no crawling. The SEC offers no support for scripted access. There are no terms against a desktop app using it.
- An unknown CIK is a `404` with an S3 XML body, not JSON (`submissions-unknown-CIK-404.xml`).

| Endpoint | Size | Use |
|---|---|---|
| `www.sec.gov/files/company_tickers_exchange.json` | 523 KB (181 KB gzipped), 10,430 rows | `{fields: [cik, name, ticker, exchange], data: [[…]]}`. Exchange is `Nasdaq`, `NYSE`, `OTC`, `CBOE`, `TXSE` or `null`. Share classes use a dash (`BRK-B`). Last modified 2026-10-26; the SEC publishes no refresh schedule. Download once per launch, in memory. |
| `www.sec.gov/files/company_tickers.json` | 798 KB | Same without exchange. Not needed. |
| `data.sec.gov/submissions/CIK##########.json` | 164 KB for AAPL | `name`, `tickers`, `exchanges`, `sic`, `sicDescription` ("Electronic Computers"), `fiscalYearEnd` ("0926"), `website`, addresses, and the latest 1,000 filings as parallel arrays with accession numbers and `primaryDocument`. SIC is too fine to stand in for sector; Equibles' screener has the real one. |
| `data.sec.gov/api/xbrl/companyfacts/CIK##########.json` | **3.8 MB** for AAPL | Every us-gaap fact (503 concepts), all periods. Raw tags and duplicates; mapping them to statement lines is the work Equibles already does. Not recommended. |
| `data.sec.gov/api/xbrl/companyconcept/…/{tag}.json` | 18 KB | One tag. Same objection. |
| `browse-edgar?action=getcompany&CIK=…&output=atom` | 13 KB | Per-company Atom feed of new filings. No use without polling, which the epic rules out. |

## Finnhub

Free key. `X-Finnhub-Token` header. **60 calls/minute** (`x-ratelimit-limit: 60`). Terms: every plan is personal use only, with no redistribution, so each user would need their own key (a second Keychain account, entered in Settings).

| Endpoint | Free? | Notes |
|---|---|---|
| `/search?q=` | Yes | Name or symbol search, worldwide (includes `603020.SS`); filter with `exchange=US`. |
| `/stock/profile2` | Yes | `name`, `exchange` ("NASDAQ NMS - GLOBAL MARKET"), `finnhubIndustry` ("Technology"), `marketCapitalization` **in millions**, `ipo`, `logo`, `weburl`. Unknown ticker: `200 {}`. |
| `/company-news` | Yes | About a year back (April 2026 returned rows, October 2025 none); about 250 items per request. Fields: `headline`, `source` (mostly Yahoo, Benzinga, CNBC), `summary`, `datetime` (Unix), `image`, `url` (a finnhub.io redirect). Unknown ticker: `200 []`. |
| `/stock/metric?metric=all` | Yes | 133 metrics (P/E, 52-week range, dividend yield, margins); 243 KB with `series`. |
| `/stock/financials-reported` | Yes | As-filed XBRL with raw `us-gaap_` concepts, like EDGAR. 558 KB. |
| `/stock/dividend`, `/stock/dividend2`, `/stock/candle`, `/stock/profile`, `/press-releases` | **No** | `403 {"error":"You don't have access to this resource."}` (`premium-403.json`). |

Finnhub's unique value here is third-party news. Search and profile are covered by EDGAR and the Equibles screener without a second key.

## Fixtures

`equibles/`, `edgar/` and `finnhub/` hold the responses named above. Long arrays are cut to a few rows (and `meta` left as returned), so counts in `meta` can exceed the rows shown. Headers aren't committed. No file contains an API key or the User-Agent's email.
