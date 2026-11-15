# Tier lists — release verification

## Implemented in the release-polish pass

- Stable eager board cells; insertion markers and destination/position hint, exact
  grab offset, empty-pool drop geometry, out-of-board cancellation, scroll/back
  gesture priority and cleanup on teardown/app inactivity. No tilt/redesign.
- Named accessible poster actions; tapping offers tier routing without a drag.
  Undo covers board/content changes; local save covers description, backgrounding
  and leaving the editor, but is suppressed after successful publication.
- Account-scoped drafts/social state with conservative owner-proven legacy draft
  migration; no automatic deletion of the 21st draft. Guest work stays guest work.
- Ordered picker selection; existing titles are marked/disabled. Search cancellation,
  stale collection response guards, explicit search/retry/empty states.
- Validated publication; existing-list ETag conditional writes preserve live social
  counts and refuse concurrent replacement/deletion. Errors retain the draft.
  Authors can edit existing lists; remix IDs are stable for the editing session.
- Author history scans indexed `$key` pages rather than the global latest 100.
  This needs no new production rules/index. At large scale replace the scan with
  a server-maintained author index; do not silently cap author results.
- Checked social writes, in-flight coalescing and ETag counter updates with bounded
  contention retry. Failed operations do not show false local success.
- Standard SwiftUI swipeActions deletion and error UI, forced feed refresh, authoritative empty feed. Swipe deletion does not open a second confirmation dialog.
- Real share sheet presentation, export request coalescing, six-image download
  batches, thumbnail decoding, explicit renderer pixel scale/24 MP budget and
  tall-board fitting in stories. Export uses effective/current curated poster URLs.

## Automated evidence

`bash sloosh-iOS/Tests/run-tier-list-tests.sh` compiles the production models,
draft store, move reducer and repository. Isolated UserDefaults + URLProtocol
exercise account migration/isolation/deletion, forward/backward/boundary moves,
invalid targets, duplicate/empty/title validation, 412 counter contention, failed
writes, conditional publication retaining counters, author pagination across 100+
records, empty feed replacement. Tests never call production Firebase.

CI also runs the existing artwork, typography, rendering, auth, playback policy,
watch-party and other regression suites, then compiles/packages the iOS app.
No Linux SwiftUI compile or simulator/on-device success is implied.

## Required hands-on release smoke test (not yet performed here)

- Small iPhone + iPad, light/dark, large type, VoiceOver, Reduce Motion.
- Tap, quick swipe, long hold; drag forward/backward within wrapped rows, between
  levels, to an empty level/pool; release outside board. No unintended tap after
  hold, no sticky scroll or missing/duplicated title. Test with keyboard initially up.
- Long board: hold still at both edges, vary speed, reverse direction; cancel with
  app switch/back/rotation. Verify 60/120 Hz smoothness and unlocked scroll on return.
- Undo a move/removal/row edit/add; close and reopen; background during editing.
  Publish and return: no resurrected draft. Change accounts while editor is open.
- Picker: ordered multi-select, already-present film, movie/TV same numeric ID,
  fast queries/collection switches, failed next-page retry, missing posters.
- Publish/edit/delete offline or denied; draft survives and no success UI lies.
  Two devices edit one list; a concurrent edit/delete must not be overwritten.
- More than 100 global lists: older author lists remain available. Pull to refresh
  must actually refresh popular content and show a useful failure/empty state.
- Export empty/missing posters, long titles and 200+ films; check memory on a real
  device, complete full-board output, centered fitted stories, Photos permission
  denial, native activity sheet dismissal and return to normal navigation.
- Chat/channel links, external links, cold start and profile deep-link navigation.

## Server-side limitations / public-release gates

No live database/rules/backend modifications are made by this change. The existing
Firebase rules allow authenticated counter writes but do not expose per-user
like/view markers for reading. Consequently social dedup/state is per account on
this installation, not globally exactly-once across reinstall/multiple devices.
Marker + counter writes are compensated best-effort, not a single server
transaction. True global exactly-once engagement and tamper-resistant counts need
server-owned aggregation/transactions + appropriate rule deployment. Client ETag
retry fixes lost simultaneous counter increments; it cannot provide that guarantee.

Parent marker cleanup on delete remains subject to existing rules. A failed fetch
can display the last confirmed cached list; a deleted offline item is not proof of
remote existence. Do not label the public release fully verified until the above
device and live Firebase scenarios are checked.

## Admin template management and navigation polish

- Details no longer has a tier-list action; the Profile entry sits beside the
  avatar, leaving Downloads + Settings on the right. Deletion uses native
  SwiftUI `swipeActions(edge: .trailing)` as in d5b1207, with a destructive Button,
  a system trash Label and red tint. Default full swipe stays enabled. There is no
  hand-built gesture/background or second confirmation popover after a swipe,
  including admin templates. Remote rows update only after checked server success;
  failed requests still show an error. Non-swipe editor discard protection remains.
- Admin → Тир-листы uses the existing `tier_templates` Firebase rule (admin UID).
  Create/edit title, description and priority; add from the shared film picker,
  remove/reorder films with native handles. At least four unique films are required;
  the first four determine the template cover. Cancel warns about unsaved edits.
- Durable checked, conditional writes reject permission/network failure, stale
  admin edits, concurrent deletes and deleted-record resurrection. Template fetches
  fence old responses, accept root null, force-refresh on gallery entry/pull and
  use the existing admin Refresh action. No live database writes are run by tests.
- Future template edits require no new IPA; users load the current remote version.
  Existing drafts/publications are independent copies and are deliberately not
  rewritten. The initial admin UI itself requires installing this client build.
- Verify on device: profile title spacing and taps, Details action removal, native
  swipe red/white contrast in both themes; admin save/cancel/reorder/remove/add,
  lost permissions, two-admin conflict and visibility after refresh on another
  device. Production rules must already grant the current admin UID access; errors
  are surfaced rather than treated as successful saves.
