# Catalog search: client redesign and server release gates

## Scope and verified contract

The client keeps the existing authenticated `api/v1/search?query&page` title endpoint
and `api/v2/search` discovery endpoint. No guessed server endpoints, bundled
credentials, provider requests, server deployments or production-rule changes.

The separate private `sluvskii/sloosh-api` repository returned HTTP 403 (resource
not accessible by integration) during this session. Vercel's available connector
cannot read/edit that repository or execute authenticated catalog acceptance
queries. Server search indexing, full-catalog recall, metadata completeness and
fresh-release ingestion are NOT verified by client unit tests or an IPA build.
This work must not be described as universal typo correction or finding every
project. It is a substantive client stage, not the completed server redesign.

## Client behavior

- One debounced task per normalized query/filter identity. Invalidate the previous
  generation synchronously before debounce, ignore canceled/late completions, and
  freeze the request/filter snapshot. Clear returns immediately to discovery.
- Submit bypasses debounce. History records only explicit submit/title opening,
  stores at most 20 normalized unique queries, is UID-scoped and can be deleted.
  Do not import the old global history into another account's history.
- Native completions use history, observed result titles/original titles and the
  current popular shelf; bounded edit distance includes adjacent swaps. They are
  not a server-wide spelling dictionary or an invented list of projects.
- A successful empty, unfiltered first page with no later pages can try at most
  two keyboard-layout/transliteration alternatives. Never reinterpret network
  failure as a spelling error or replace a nonempty primary result. Disclose the
  resolved query; use the SAME resolved query on subsequent pages.
- No poster/rating/release-age gate in title search. Original-title-only records
  and posterless new releases are retained, with existing card placeholders.
  Keep raw API/playback IDs; deduplicate cells by typed artwork identity both
  between pages and within a page. Preserve server relevance order on ties.
- Advance pagination only after success. Keep earlier content on append failure,
  show an inline retry, repeat the failed page, and merge/sort all loaded items.
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
  exactly, not by arbitrary substring. Missing title-search metadata cannot prove
  a filter match. On server-filtered discovery pages omitted metadata is trusted
  as filtered by the existing server contract; known contradictions are rejected.
- Never restore an unfiltered page because a selected filter eliminated it.
  Never substitute a studio-name title search for a studio collection in filtering.
- Unsupported title+studio filtering is not offered in the Search filter sheet;
  studios remain available via discovery collections and Home filters. A
  programmatic title+studio combination errors explicitly rather than ignoring
  the studio. Popularity is not offered as a local title sort without popularity
  metadata. Title year/rating sorts say "по загруженным результатам"; global
  sorted filtered title pagination needs a server contract.

## Automated CI

`bash sloosh-iOS/Tests/run-catalog-search-tests.sh` compiles the real DTOs, query/
filter/transport policies and observable search state machine, with injected
transport adapters. Covers query normalization, ё/е, keyboard recovery, bounded
fuzzy suggestions, typed identities, posterless/new titles, filter aliases and
unknown metadata, range/query encoding, late-response races, debounce, history,
append failure/retry, empty-page scanning and resolved-query pagination.

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

## Server stage (blocked pending repository access)

1. Review current search/index source and documented v1/v2 capabilities, metadata
   provenance, paging limits, cache headers/TTLs, fuzzy ranking and ingestion lag.
2. Create an authenticated acceptance set: exact/original/alternate titles,
   sequels/numbers, Cyrillic/Latin, ё/е, punctuation, common typos, same-name works,
   film/TV same numeric ID, anime, obscure/older films and freshest announced and
   released projects. Record expected typed IDs, not just whether anything matched.
3. Measure top-1/top-5 recall, empty rate, false correction rate, p50/p95 latency
   and fresh-release lag before/after changes. Test each filter and combinations,
   missing metadata, deterministic global sort/cursor and deduplication.
4. Implement server-side normalized aliases/fuzzy suggestions, combined title +
   structured filtering, explicit unknown metadata behavior, stable ranking and
   correct totals/cursors. Bound fan-out, rate-limit, cancel expensive work and
   use short/negative-aware freshness caching. Do not cache an absent new title
   indefinitely or confuse searchable catalog presence with playable availability.
5. Verify in a preview with authenticated requests before changing production.
   Preserve auth, regional gateway failover and all playback endpoints.
