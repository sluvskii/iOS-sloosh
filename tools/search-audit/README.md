# Read-only audit of the published search API

This diagnostic reproduces current behavior of `sluvskii/sloosh-api` at
`77665388051de9685632db41c5222e01dbfcacc7`. It does **not** modify or deploy that
repository. Fifteen assertions confirm observed defects/limitations; a green run
means those observations reproduced, **not** that server search is correct.

```bash
npm ci --prefix tools/search-audit --ignore-scripts
npm --prefix tools/search-audit run audit
```

Requirements: Node 22+, npm, and `gh` with read access to the now-public repository.
No catalog credentials, Firebase ID tokens or Vercel access are needed. Never
paste production secrets into the runner. The only outbound API calls made by
this runner are GitHub source reads; catalog `fetch` is replaced with fixtures
and rejects any host other than `catalog.invalid`.

The runner downloads five pinned public source files into an ignored temporary
`.work/` directory. The real Hono search route, search/discover service, country
mapping, DTO types and LRU cache are used unchanged. Artwork/config/stream imports
are stubbed, with mutation and playback adapters forbidden. The two router aliases
are mounted as shown by the upstream `src/index.ts`; the application security and
CDN middleware are not mounted. Their source is reviewed separately in the report.
Date is frozen at 2026-10-27 for deterministic date-bound checks. Temporary source
files are deleted even on failure. Dependencies are isolated from the iOS build.

These are source-level fixtures, not live recall/latency/security tests. In
particular they do not establish which commit currently runs in production or
how the real upstream handles a typo. See
[`docs/catalog-search-server-audit.md`](../../docs/catalog-search-server-audit.md)
for findings and the server implementation/acceptance plan.

## Full-title vs suggestion regression on the merged server

```bash
node tools/search-audit/run.mjs --full-title
```

This mode pins the merged server `d6a0b1fb428aff4977ea78dedfa3b995521ddcba`,
uses the real search/suggestion service and a controlled upstream fixture where
a franchise query returns a title but its full spelling returns no text hits.
It demonstrates that the dictionary can offer an exact typed title while title
search still returns empty (exact keys are excluded from typo candidates).
It is a reproduction of that gap, NOT proof of live upstream behavior or a
correctness gate. See `docs/search-full-title-regression.md` for client fixes,
limits and required device checks. The original audit mode remains unchanged.
