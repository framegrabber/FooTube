# Self-hosted sync (Cloudflare)

## Problem Statement
How might we keep subscriptions, Watch Later, history/resume positions and SponsorBlock settings the same across a household's 2–3 Apple TVs, and later iPhone/iPad, without the paid Apple Developer Program (CloudKit), a Google login, or a server anyone else controls?

## Recommended Direction
Local-first with a snapshot relay. Every device keeps its full state in `UserDefaults` as today and works without network or without sync configured. Each builder deploys their own Cloudflare Worker with D1 on a free account, from the separate repo `FooTubeSyncBackend`. The Worker stores one versioned JSON document per store and overwrites it only if the client's version matches (`UPDATE … WHERE version = ?`). It never reads or merges contents; all merge rules live in FooTubeCore as pure functions tested offline with fixtures.

Devices pull when the app comes to the foreground and push a few seconds after a change; on a version conflict they pull, merge and retry. Auth is one household secret: it and the Worker URL go in a gitignored xcconfig (like `Config/Signing.local.xcconfig`) and are baked into Info.plist, so there is no typing on the TV and no login screen. Without a configured URL, sync is off.

The iPhone/iPad app is a second project: a multiplatform XcodeGen target on the same FooTubeCore and the same sync, started once two Apple TVs sync reliably. A third project adds "Watch Later from the browser" through a bookmarklet and an inbox on the Worker.

### Merge rules
- **Subscriptions, Watch Later:** entries keyed by ID with a change time and an optional `removedAt` deletion marker; the later timestamp wins. Markers are dropped after 90 days.
- **Older devices:** each device stores `lastSyncAt`. An entry missing on the server and unchanged locally since `lastSyncAt` was deleted elsewhere and is dropped; only entries edited after the last sync are pushed back. This keeps a TV unused for more than 90 days from resurrecting deletions.
- **History:** per video, the newest `updatedAt` wins; `watched` stays set if any device set it; the 500-entry cap applies after merging. "Clear history" stores a `clearedAt` cut-off; older entries from other devices are dropped.
- **SponsorBlock settings:** the whole document from the device that changed it last.
- **Clocks:** device clocks are assumed roughly correct (network time); acceptable for one household.

### Contract between app and Worker
Recorded in `FooTubeSyncBackend/SPEC.md` (section "Contract"); both repos implement against it.
- `GET /v1/stores/:name` → document and `ETag`. `PUT /v1/stores/:name` with `If-Match` (or `If-None-Match: *` to create) → new `ETag`, or `412` with the current document.
- `Authorization: Bearer <household token>` on every store request.
- Inbox: add-only token, accepted only for adding video IDs; apps fold inbox entries into Watch Later on their next sync and fetch title and thumbnail themselves.
- FooTubeCore tests the contract offline against recorded responses, plus an opt-in network test against `wrangler dev` gated on `FOOTUBE_SYNC_TEST_URL` / `FOOTUBE_SYNC_TEST_TOKEN` (localhost only). No secret is committed in either repo.

### Bookmarklet
Opens `https://<worker>/add?v=<id>#<inbox token>` in a new tab; the Worker's small page sends the request itself. This avoids YouTube's content security policy blocking a request from inside youtube.com [unverified], and the token after `#` never reaches server logs. A leaked bookmark (bookmarks sync through browser clouds) can only add videos to Watch Later.

## Key Assumptions to Validate
- [ ] D1's conditional update prevents lost writes under concurrent pushes. Test: two scripted clients racing against `wrangler dev`.
- [ ] Sync on foreground plus a few seconds after changes feels immediate on tvOS, which has no background refresh. Test: subscribe on TV A, open TV B, time it.
- [ ] Sending the whole history (500 entries, ~55 KB) on every playback stop is cheap enough. Test: measure request time on the Apple TV HD.
- [ ] Migrating v1 stores to v2 (change times, deletion markers) loses nothing. Test: fixture with current v1 data.
- [ ] YouTube's CSP blocks an in-page request from a bookmarklet, so the new-tab design is needed. Test: try both in Safari and Chrome.
- [ ] Free-team limits on iPhone/iPad (7-day re-signing, 3 sideloaded apps per device) are acceptable. Check before starting the iOS project.

## MVP Scope
In:
1. SPEC Boundaries (Never/Ask-first) and `PRODUCT.md` updated to allow sync to the builder's own Worker; the contract recorded in SPEC.
2. Core: v2 stores with change times and deletion markers plus v1 migration; merge functions; a `SyncEngine` (pull, merge, push, retry on `412`), off without configuration.
3. `FooTubeSyncBackend`: TypeScript Worker with D1, `GET`/`PUT /v1/stores/:name`, version check, bearer auth, vitest tests, deploy steps in its README.
4. tvOS: sync on foreground and after changes; sync status in Settings.
5. Verification: Simulator and Apple TV HD against the same Worker, all four stores.

Out: the iPhone/iPad app (next project) and the browser inbox and bookmarklet (after that).

## Not Doing (and Why)
- Workers KV: no conditional writes, 1,000 writes/day on the free plan, up to 60 s until other locations see a change.
- Merging on the server: Swift and TypeScript copies of the merge rules would drift; the server stays a mailbox.
- CRDT libraries or per-record change logs: a dependency and complexity one household doesn't need.
- Accounts, pairing codes, several households per Worker: one Worker per household, secret baked in at build time.
- A hosted instance for other builders: their watch data on someone else's account.
- Live push / "send to TV": needs a Durable Object with a live connection; revisit after the iOS app exists.
- Syncing the feed and image caches: rebuilt locally.
- Local-network (Bonjour) sync: doesn't reach devices away from home; not worth a second sync path.

## Open Questions
- Remote URL of `FooTubeSyncBackend`, to link from the README setup section.
- Does the add-only inbox token need an expiry, or is rotating it by redeploying enough?

## Decisions
- Worker in a separate repo, `FooTubeSyncBackend`; this repo needs no Node toolchain.
- Deletion markers kept 90 days, made safe by the `lastSyncAt` rule.
- Bookmarklet holds a separate add-only inbox token, not the household secret.
- Backend dependencies approved: wrangler, TypeScript, vitest (in `FooTubeSyncBackend` only).
