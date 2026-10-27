# Spec: sync-client

Module `sync-client` of FooTube's self-hosted sync (capability map: `SYNC.md`; background: `docs/ideas/cloudflare-sync.md`). Builds against the Contract in `FooTubeSyncBackend/SPEC.md` (module `sync-backend`). The rest of FooTube's rules (`SPEC.md`, `CONSTRAINTS.md`, `AGENTS.md`) apply unchanged unless this spec says otherwise.

Written and planned overnight on 2026-10-26 without the owner's review of this file (owner asked to go as far as possible); decisions taken alone are listed under **Decisions to review**.

## Objective
Subscriptions, Watch Later, History (with resume positions) and SponsorBlock settings are the same on every Apple TV of a household that points FooTube at the household's own sync Worker. Without a configured Worker, FooTube behaves exactly as today.

**Stories:**
1. As a viewer, I subscribe to a channel on the living-room TV and it's in Subscriptions on the bedroom TV the next time I open FooTube there.
2. As a viewer, I stop a video on one TV and continue at the same position on another.
3. As a viewer, I remove a video from Watch Later or unsubscribe on one TV and it doesn't come back from another TV, even one that was off for months.
4. As a viewer, I clear History on one TV and it's cleared on all.
5. As a builder, I connect a TV to my Worker by running `scripts/run-device.sh` once with my Worker's URL and token in the environment; I can see in Settings whether sync works and when it last synced.
6. As a viewer, a missing network or a broken Worker never blocks browsing or playback; FooTube keeps working on local data and catches up later.

## Data formats (shared by local storage and the Worker)
Each store is one JSON document with `"format": 1`. The Worker stores it as is; the local copy in `UserDefaults` is the same document. Dates are ISO 8601 with fractional seconds, UTC.

| Store | Document |
|---|---|
| `subscriptions` | `{"format":1, "entries":[{"id","name","avatar"?,"changedAt","removedAt"?}]}` |
| `watchLater` | `{"format":1, "entries":[{"video": VideoSummary, "addedAt","changedAt","removedAt"?}]}` |
| `history` | `{"format":1, "clearedAt"?, "entries":[WatchEntry]}` (WatchEntry as today: `videoID`, `position`, `duration`, `updatedAt`, `watched`, `video`?) |
| `skipSettings` | `{"format":1, "changedAt"?, "overrides":{category: behavior}}` |

Local keys: `subscriptions.v2`, `watchLater.v2`, `watchHistory.v2`, `skipSettings.v2`; sync bookkeeping `sync.state.v1` (per store: `lastSyncAt`). On first launch of the new build each store migrates its v1 key into v2 and removes the v1 key (clean cutover): subscriptions and settings get `changedAt` = migration time (settings only if they differ from the default), Watch Later entries get `addedAt` = migration time minus their index in seconds (keeps the order), history entries keep their `updatedAt`.

A document with a `format` greater than this build knows is never overwritten and never merged; that store's sync stops with the status "Update FooTube on this device".

## Merge rules
Pure functions in FooTubeCore: `merge(local, remote, lastSyncAt, now) -> merged`. Every device computes the same result from the same two inputs (deterministic), so devices converge and don't push back and forth.

- **Subscriptions, Watch Later:** union by key (`id`, `video.id`). For a key on both sides the entry with the later `changedAt` wins; on equal `changedAt` a removal wins, then the lexicographically greater canonical JSON. Removing sets `removedAt` = `changedAt` = now; re-adding clears `removedAt`. Removed entries are hidden from the app and dropped once `removedAt` is older than 90 days.
- **Pruned-elsewhere rule:** a live local entry that is missing on the server, while the server document exists, and whose `changedAt` is before this device's `lastSyncAt` for that store, was deleted on another device and its marker already pruned: it is dropped. Entries changed at or after `lastSyncAt` are kept and pushed (an edit in the same millisecond as the read that set `lastSyncAt` may not have reached the Worker). A device that never synced (`lastSyncAt` nil) keeps everything, so the first sync of an existing TV unions its data with the server's.
- **History:** per `videoID` the entry with the later `updatedAt` wins (equal: greater `position`); `watched` is true if either side has it; `video` falls back to the other side's summary when the winner has none. `clearedAt` is the later of both sides; entries with `updatedAt` at or before it are dropped. Then newest first, capped at 500.
- **SponsorBlock settings:** the whole document with the later `changedAt` wins; a document without `changedAt` (never changed) loses to any other. "Restore Defaults" is a change (empty `overrides`, new `changedAt`).
- **Clocks:** device clocks are trusted (network time). A `changedAt`/`updatedAt` more than a day in the future is treated as now when it is merged in.

## Sync engine
- **Round for one store:** `GET` → merge with local → if the merged document differs from the server's, `PUT` with `If-Match` (the server's `ETag` verbatim, also a weak `W/"n"` from the edge) or `If-None-Match: *` after a `404` → on `412` merge again with the document in the response and retry, at most 3 attempts per round → once the server has the merged document (stored, or already up to date): merge it into the local document as it is now, save if that changed (models reload), and set `lastSyncAt` to the time the local document was read for the successful merge. A failed round leaves local data untouched: saving the server's changes before they reached the server would let a later round treat them as already synced (pruned-elsewhere) although the server never got them. Exception: browser-inbox items are folded into Watch Later locally before their push round (`SPEC-browser-inbox.md`); they stay in the inbox until that push succeeds.
- Local read, merge and save happen on the main actor, where every store write already happens, so a change made while a request is in flight is never lost: the final merge keeps it (changed at or after `lastSyncAt`) and it schedules another round. When the app goes to the background, stores with a pending change and stores whose round is still in flight are synced inside the background task.
- **When:** all four stores when the app becomes active and every 5 minutes while it stays active; one store 3 s after a local change to it (history: 30 s, since playback records every 5 s, and right away when the player closes); all stores with a pending change when the app goes to the background (inside a background task); "Sync Now" in Settings.
- **Failures:** network errors, `5xx` and timeouts (10 s) leave local data untouched and retry at the next trigger; `401` stops sync until reconfigured and shows "Token rejected"; nothing is ever shown as an alert, only in Settings.
- **Logging:** `os.Logger` category `sync`: store, status code, attempt, merged entry counts. Never the token, never titles or video IDs.

## Configuration
- A configuration file `Library/Caches/footube-sync.json` (`{"url": …, "token": …}`) in the app's data container: at launch the app reads it, deletes it whether valid or not (logging only the error message), and saves the URL in `UserDefaults` and the token in the Keychain (generic password, this app only). `-syncReset YES` (launch argument, no secret) removes both and the sync state, keeping local data.
- `scripts/run-sim.sh` and `scripts/run-device.sh` write that file (mode 600, deleted when the script exits) when `FOOTUBE_SYNC_URL` and `FOOTUBE_SYNC_TOKEN` are set, or read them from the file `$FOOTUBE_SYNC_ENV` (default `~/.config/footube/sync.env`) when it exists, and copy it into the installed app's container before launch (`simctl get_app_container … data` / `devicectl device copy to --domain-type appDataContainer`). The token never enters the repository, the app bundle, the build settings or a launch command.
- The URL must be `https`, except `http://localhost` / `http://127.0.0.1` (Simulator against `wrangler dev`).

## Settings
New section **Sync** above History: a row with the state ("Off", "Synced 2 minutes ago", "Syncing…", "Offline, will retry", "Token rejected", "Update FooTube on this device") and a **Sync Now** button (hidden when off). Descriptions explain where the data goes. Texts that say data "stays on this Apple TV" (Version, Clear History, expiry) say instead that it syncs to the household's own server when sync is on. All new strings in `App/Localizable.xcstrings` with German.

## Tech Stack
Unchanged (Swift 6.2, SwiftUI, FooTubeCore, Swift Testing). `URLSession` for the Worker, `Security` framework for the Keychain. No new dependencies.

## Commands
Existing commands, plus:
```
Local Worker:     (in ../FooTubeSyncBackend) npm run dev               → http://localhost:8787, token from its .dev.vars
Sync network test: FOOTUBE_SYNC_TEST_URL=http://localhost:8787 FOOTUBE_SYNC_TEST_TOKEN=<dev token> swift test --package-path Packages/FooTubeCore --filter SyncNetworkTests   (localhost only)
Simulator w/ sync: FOOTUBE_SYNC_URL=… FOOTUBE_SYNC_TOKEN=… scripts/run-sim.sh
Device w/ sync:    FOOTUBE_SYNC_URL=… FOOTUBE_SYNC_TOKEN=… scripts/run-device.sh   (or ~/.config/footube/sync.env)
```
The sync network test writes to the Worker's stores: run it only against `wrangler dev`, never against the household's Worker.

## Project Structure
```
Packages/FooTubeCore/Sources/FooTubeCore/
  SyncDocuments.swift      → the four document types, format check, canonical encoding
  SyncMerge.swift          → merge rules
  SyncClient.swift         → Contract over URLSession (GET/PUT, ETag, typed SyncError)
  SyncEngine.swift         → rounds, retries, lastSyncAt, schedule-independent
  SyncConfiguration.swift  → URL + token loading/saving (UserDefaults + Keychain), configuration file, -syncReset
  SubscriptionStore.swift, WatchLater.swift, WatchHistory.swift, SkipSettings.swift → v2 documents + v1 migration, same public API plus document access
Packages/FooTubeCore/Tests/FooTubeCoreTests/
  SyncMergeTests, SyncMigrationTests, SyncClientTests (URLProtocol stub, responses recorded from wrangler dev in Fixtures/sync/), SyncEngineTests, SyncNetworkTests (opt-in)
App/SyncModel.swift        → triggers (scene phase, timers, debounced changes, background task), status for Settings, reloads the models
App/SettingsView.swift, App/FooTubeApp.swift, App/*Model.swift, App/Localizable.xcstrings
scripts/run-sim.sh, scripts/run-device.sh
```

## Code Style
As `SPEC.md`. Merge functions are free of I/O and time (`now` is a parameter). Example of the intended shape:

```swift
public struct SubscriptionsDocument: Codable, Hashable, Sendable {
    public var format = 1
    public var entries: [SubscriptionRecord]
}

public enum SyncError: Error, Hashable, Sendable {
    case offline(detail: String)
    case unauthorized
    case server(status: Int)
    case unsupportedFormat(Int)
    case conflictPersisted
}

public func merge(_ local: SubscriptionsDocument, _ remote: SubscriptionsDocument?, lastSyncAt: Date?, now: Date) -> SubscriptionsDocument
```

## Testing Strategy
- **Merge (offline, most tests):** each rule above, tie-breaks, determinism (`merge(a, b) == merge(b, a)` where the rules are symmetric), the pruned-elsewhere rule with and without `lastSyncAt`, 90-day pruning boundary, future timestamps, history cap and `clearedAt`.
- **Migration:** v1 fixtures of all four stores → v2 with order, positions, watched marks and settings intact; v1 keys removed; unreadable v1 → empty.
- **Client:** every Contract status mapped to the right result/`SyncError`, `ETag` passed through untouched, recorded `wrangler dev` responses as fixtures.
- **Engine:** two simulated devices against an in-memory fake Worker that implements the Contract (version check included): subscribe/unsubscribe/re-subscribe across devices, concurrent edits, a 412 retry, a device offline for 100 days, a newer `format` on the server.
- **Network (opt-in):** the same two-device scenario against `wrangler dev`.
- **App:** two Simulators (`Apple TV` and `Apple TV 4K (3rd generation)`) against `wrangler dev`: subscribe, Watch Later, resume position and settings appear on the other; screenshots in `tasks/results.md`. Device: owner on the Apple TV HD.

## Boundaries
- **Always:** keep merge rules in FooTubeCore with tests; keep local-first behaviour (sync failures never block the UI); update `SPEC.md`/`PRODUCT.md` wording about where data lives.
- **Ask first:** changing a document format (bump `format`, plan the migration); sending anything to a host other than the configured Worker.
- **Never:** put the token in the repo, the bundle, build settings, logs or screenshots; let sync block launch or playback; show sync errors as alerts.

## Success Criteria
1. With sync configured on two Simulators, a subscription, a Watch Later entry, a resume position and a SponsorBlock setting made on one appear on the other within one foreground of the second (≤ 10 s on a normal connection).
2. An unsubscribe and a Watch Later removal on one device are not undone by the other, including when the other was offline across the change and when its last sync is more than 90 days old (engine test).
3. Clearing History on one device clears it on the other.
4. Without configuration: no request to any new host, identical behaviour to today (all existing tests pass); with the Worker unreachable: browsing and playback unaffected, Settings shows "Offline, will retry".
5. Existing v1 data of all four stores survives the upgrade (migration tests and a Simulator upgrade from the previous build).
6. `scripts/check.sh task` exits 0.

## Changes to SPEC.md and PRODUCT.md (part of this module)
- `SPEC.md` Boundaries → Never: "send watch data anywhere except the SponsorBlock hash-prefix lookup **and the sync Worker the builder configured**". Ask first: "any network request to a host other than YouTube, SponsorBlock **or the configured sync Worker**".
- `SPEC.md` Out of Scope: remove "Subscription sync/backup"; Tech Stack mentions the sync Worker; Decisions Recorded links `SYNC.md`.
- `PRODUCT.md`: Product Purpose, Positioning, Capabilities (state lives in `UserDefaults`, optionally synced to the builder's own Cloudflare Worker), Principle 2 becomes "Nothing leaves the household: no account, no third-party server, no telemetry; the only server is the one the builder runs".

## Decisions to review
- **Config by a file dropped into the app container + Keychain, not an xcconfig and not launch arguments.** A token in a gitignored file inside the repo would be flagged by `gitleaks dir` (which scans ignored files too) and would need a CONSTRAINTS exception; base64 tokens can also contain `//`, which starts a comment in xcconfig. The first implementation passed `-syncURL`/`-syncToken` as launch arguments, but the system logs launch arguments: the Simulator's unified log (CoreSimulatorBridge, launchd) showed the full token after one `simctl launch`, and `devicectl` launches are logged on the device the same way. The scripts now copy a temporary file into the app's data container (`Library/Caches`, which exists and is app-writable on tvOS), and the app deletes it at the next launch; Keychain and `UserDefaults` survive the weekly rebuild. Changed by the lead on 2026-10-26 after that finding.
- **v1 keys removed after migration.** Installing an older build afterwards would start empty; accepted for a clean cutover.
- **History pushes 30 s after the last change**, not on every 5 s record, plus on leaving the player and on backgrounding.
- **Settings sync whole-document last-writer-wins**, not per category.
