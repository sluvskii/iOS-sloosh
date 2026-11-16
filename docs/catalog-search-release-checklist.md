# Catalog search: client redesign and server release gates

## Scope and verified contract

The client integrates the additive contract in
[`sloosh-api@80b0048`](https://github.com/sluvskii/sloosh-api/tree/80b0048),
[draft server PR #1](https://github.com/sluvskii/sloosh-api/pull/1).
`api/v1|v2/search` and `/discover` share the same explicit contract; suggestions
use the authenticated `api/v1/search/suggestions` endpoint. No bundled credentials,
production-rule changes, server deployment or playback endpoint changes here.

The 15 historical observations at API `7766538` have server-side resolutions in
that branch; see `catalog-search-server-audit.md` for per-item status, contract and
test links. Server verification reports 80/80 automated and 20/20 mock-preview
checks. Those are not live-catalog recall or production freshness measurements.
The pinned diagnostic in `tools/search-audit/` reproduces the OLD revision only.
The server PR is still draft/open; deployment and device acceptance are pending.

## Client behavior

- Literal `+` in title queries is percent-escaped, not interpreted as a space by
  form-style server query parsers. Canceled catalog requests stop before retry.
- One debounced task per normalized query/filter identity. Invalidate the previous
  generation synchronously before debounce, ignore canceled/late completions, and
  freeze the request/filter snapshot. Clear returns immediately to discovery.
- Submit bypasses debounce. History records only explicit submit/title opening,
  stores at most 20 normalized unique queries, is UID-scoped and can be deleted.
  Do not import the old global history into another account's history.
- Server completions use ≥300 ms debounce, cancellation and generation fencing.
  On failure/empty suggestions, history/observed titles/popular-shelf completions
  remain available; those are not a complete search index. Private history stays
  account-local. Clearing input immediately clears server completions.
- New-contract responses own correction: show resolved query, original string
  and correction reason; freeze resolved query for following pages. Never run
  client correction over a versioned or already corrected response. Only a legacy
  response without a contract marker can use the old bounded keyboard fallback.
  No spelling fallback after network errors. There is no server flag yet for
  forcing an uncorrected repeat, so no nonfunctional override button is offered.
- No poster/rating/release-age gate in title search. Original-title-only records
  and posterless new releases are retained, with existing card placeholders.
  Keep raw API/playback IDs; deduplicate cells by typed artwork identity both
  between pages and within a page. Preserve server relevance order on ties.
- Advance pagination only after success. Keep earlier content on append failure,
  show an inline retry and repeat the exact failed page/cursor. Use `nextCursor`
  for mixed discovery. Keep server discovery order; only title sorting is local.
  Disclose `meta.sortScope=window` as «по загруженным результатам».
  Scan at most four empty filtered pages per operation; then offer Continue.
  Empty filtered pages are NOT evidence that the entire catalog is empty.
- Applied constraints are visible as individual removable chips; removing a range
  clears both its bounds without silently changing other constraints.
- Filter sheet edits are staged. Checkmark applies atomically; Cancel/swipe-down
  leaves active filters unchanged. Reset edits the staged draft only. Explicit
  inclusive year/rating lower AND upper bounds, 1880 through current year + 3 in
  year selectors. Correct crossed bounds; locale-independent network decimals.
- Genres mean ALL selected; countries mean ANY selected; independent fields are
  ANDed. Named RU/EN and numeric genre aliases and ISO country codes are matched
  exactly, not by arbitrary substring. The new server owns filtering and unknown
  metadata handling; the client retains its accepted results even without country
  fields. `meta.insufficientMetadata` is disclosed. Legacy responses retain the
  old conservative validation, not a second implementation of the new rules.
  FILM/TV_SERIES plus an explicit animation genre is legal and may widen scope;
  never reject that combination locally as a contradiction.
- Never restore an unfiltered page because a selected filter eliminated it.
  Never substitute a studio-name title search for a studio collection in filtering.
- Search discovery genre/studio chips use this same paged search engine rather
  than older screens with different hidden quality/poster gates. Home recovery
  no longer substitutes an unfiltered cached shelf under active filters; its
  requests use the captured selection snapshot.
- Unsupported title+studio filtering is not offered in the Search filter sheet;
  studios remain available as server discovery scopes and Home filters (legacy
  servers without a contract marker retain their collection adapter). A
  programmatic title+studio combination errors explicitly rather than ignoring
  the studio. Popularity is not offered as a local title sort without popularity
  metadata. Title year/rating sorts say "по загруженным результатам"; global
  sorted filtered title pagination is not supported by the server contract.

## Automated CI

`bash sloosh-iOS/Tests/run-catalog-search-tests.sh` compiles the real DTOs, query/
filter/transport policies and observable search state machine, with injected
transport adapters. Covers query normalization, ё/е, keyboard recovery, bounded
fuzzy suggestions, typed identities, posterless/new titles, filter aliases and
unknown metadata, range/query encoding, late-response races, debounce, history,
append failure/retry, empty-page scanning, resolved-query pagination, opaque cursor
retry, modern correction without double fallback, server-order preservation,
window-scope disclosure, 400 handling and stale suggestion fencing.

These tests do not call the live catalog or validate UIKit/SwiftUI presentation.
All existing playback, artwork, auth, messenger and tier tests remain enabled.

## Required device scenarios

- Rapidly type/change/clear Cyrillic, Latin and numeric titles on slow internet;
  change filters while a request is pending; dismiss keyboard; return from Details.
  No old title results may flash under a new query. No stuck loading state.
- Try real transposed/missing-letter misspellings, transliteration and wrong
  keyboard input. Confirm corrections are understandable and original input is
  retained. Try exact obscure titles too: fallback must never replace real hits.
- Check no-results vs offline vs malformed-response vs sparse-filter pages;
  reach later matching pages; fail/retry page 2; background/foreground mid-request.
- Verify year/rating single bounds and exact intervals, movie/series/cartoon/anime,
  multiple genres/countries, studio collections, filter cancel/reset/apply and
  Dynamic Type, VoiceOver, small screens, light/dark themes and glass headers.
- Verify search result posters/logos/Details and direct Play still target the same
  typed title. Check cards with no artwork, rating, Russian title or release date.

## Release gate: real catalog and device acceptance (not yet completed)

1. Verify the deployed server revision and gateway. The implementation exists in
   draft server PR #1, not a verified production deployment. Deploying the server
   before the updated client is permitted by its backward-compatible contract.
2. Create an authenticated acceptance set of expected **typed IDs**: exact,
   original and alternative titles, sequels/numbers, Cyrillic/Latin, ё/е,
   punctuation, common typos, same-name works, film/TV same numeric ID, anime,
   obscure/older titles, fresh announcements/releases and missing artwork.
3. Measure recall@1/@5, precision/false-correction rate, empty rate, real p50/p95
   and fresh-release appearance delay. Mock-catalog p50 ≈6 ms is not real latency.
4. Test each filter and combinations, unknown metadata, branch-specific upstream
   parameters and country/exclusion combinations, duplicate-free cursor paging
   and the page-8/window boundary. Check rate-limit behavior and bounded fan-out:
   mixed discovery can cost up to 2·N upstream calls (N≤8), plus enrichment.
5. Run the required device scenarios above on the matching authenticated preview,
   then on the deployed server. Preserve Firebase JWT, admin guard, regional
   gateway failover, artwork identity and playback. Never use preview-issued
   tokens in the production app or disable authentication for acceptance.
6. Known limits: 500 pages per branch, window sorting after depth 8, observed-title
   vocabulary, enrichment ≤8 cards/page. No claim that search finds everything.
7. UX follow-up: a working “search original without correction” action needs an
   additive server flag; resending raw text alone can auto-correct again.
