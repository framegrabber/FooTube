# FooTube Task List

Every task's verification includes `scripts/check.sh task` (see CONSTRAINTS.md) plus the task-specific checks below. Commands are in SPEC.md → Commands; Simulator device is `Apple TV` (1080p, closest to Apple TV HD).

---

## Phase 0: Foundation

## Task 1: Project scaffold and tooling

**Description:** XcodeGen `project.yml` for a tvOS 18 SwiftUI app `FooTube` (bundle `com.felixrothballer.FooTube`, team `X94768F5PD`, automatic signing, `SWIFT_VERSION: 6`, `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES`); local package `Packages/FooTubeCore` (library + Swift Testing target, Swift 6 mode, warnings as errors for our targets only — verify the SwiftPM 6.2 setting against docs); `AGENTS.md` (commands, layout, conventions, and the line "Read CONSTRAINTS.md before writing code. Do not weaken it to make a change pass."); `xcode-build-server` config. App shows a placeholder screen. `.gitignore`, `.swiftformat`, `scripts/check.sh` already exist.

**Acceptance criteria:**
- [ ] App builds and launches in the `Apple TV` Simulator showing the placeholder
- [ ] An introduced warning in FooTubeCore or the app fails the build (then removed)
- [ ] LSP resolves a FooTubeCore symbol from app code

**Verification:**
- [ ] `scripts/check.sh task` exits 0 with no SKIP lines
- [ ] Manual check: Simulator screenshot; `lsp definition` succeeds

**Dependencies:** None

**Files likely touched:** `project.yml`, `AGENTS.md`, `App/FooTubeApp.swift`, `Packages/FooTubeCore/Package.swift`, `Packages/FooTubeCore/Sources/FooTubeCore/FooTubeCore.swift`, `Packages/FooTubeCore/Tests/FooTubeCoreTests/FooTubeCoreTests.swift`

**Estimated scope:** M · **Skills:** incremental-implementation, source-driven-development

---

## Task 2: Stream extraction spike in FooTubeCore

**Description:** Add alexeichhorn/YouTubeKit (local extraction only). Define `VideoID`, `ResolvedStream`, `StreamResolver`, `ResolveError` (SPEC code style) and `YouTubeKitResolver`, which selects the best muxed stream with `avc1` video ≤ 1080p and AAC audio. Offline tests over fixture stream lists for the selection rules; opt-in network test over 5 fixed IDs (normal, label music video, kids, >1 h, livestream). Cross-check with yt-dlp `android_vr`.

**Acceptance criteria:**
- [ ] Selection never returns VP9/AV1/Opus-only or > 1080p streams (offline tests)
- [ ] ≥4 of 5 non-restricted IDs resolve to a URL whose first bytes return HTTP 200/206
- [ ] Per-ID resolution/failure reason recorded in `tasks/results.md` next to yt-dlp output

**Verification:**
- [ ] `scripts/check.sh task`; `FOOTUBE_NETWORK_TESTS=1 swift test --package-path Packages/FooTubeCore`

**Dependencies:** Task 1

**Files likely touched:** `Packages/FooTubeCore/Package.swift`, `Sources/FooTubeCore/{VideoID,StreamResolver,YouTubeKitResolver}.swift`, `Tests/FooTubeCoreTests/StreamSelectionTests.swift`, `tasks/results.md`

**Estimated scope:** M · **Skills:** test-driven-development, api-and-interface-design, source-driven-development, doubt-driven-development

---

## Checkpoint A: Extraction viable
- [ ] Task 2 criteria met; otherwise stop and re-plan with the human
- [ ] code-review-and-quality on T1–T2; commit and merge to `main`

---

## Phase 1: MVP playback

## Task 3: Play a video by ID with AVPlayer

**Description:** Screen with a text field (ID or URL: `watch?v=`, `youtu.be/`, `shorts/`, `live/`; parsed in FooTubeCore) and Play. Resolves via `StreamResolver`, presents `AVPlayerViewController`. Loading and error states; errors show source client and reason. Check for playback 403s (headers).

**Acceptance criteria:**
- [ ] Known-good ID plays with audio in the Simulator, no ad
- [ ] All listed URL forms and bare IDs parse (offline tests); invalid input is rejected with a message
- [ ] Failing ID shows an error, not a blank player

**Verification:**
- [ ] `scripts/check.sh task`
- [ ] Manual check: two screenshots seconds apart show different frames

**Dependencies:** Task 2

**Files likely touched:** `App/PlayByIDView.swift`, `App/PlayerView.swift`, `Sources/FooTubeCore/VideoID.swift`, `Tests/FooTubeCoreTests/VideoIDTests.swift`

**Estimated scope:** M · **Skills:** frontend-ui-engineering, test-driven-development

---

## Task 4: Test-video list with per-video diagnostics

**Description:** Home lists the 7 MVP cases (normal, music video, age-restricted, kids, livestream, > 1 h, Short) plus free-text entry. Player overlay shows source client, resolution, codec and time to first frame; same values logged via `os.Logger`.

**Acceptance criteria:**
- [ ] All 7 entries reachable with the remote; each plays or shows an error
- [ ] Overlay and log show client, resolution, codec, time to first frame

**Verification:**
- [ ] `scripts/check.sh task`
- [ ] Manual check: screenshots of list and overlay; log stream shows the entry

**Dependencies:** Task 3

**Files likely touched:** `App/HomeView.swift`, `App/DiagnosticsOverlay.swift`, `Sources/FooTubeCore/TestVideos.swift`

**Estimated scope:** S · **Skills:** observability-and-instrumentation, frontend-ui-engineering

---

## Task 5: Deploy and run on Apple TV HD

**Description:** Human pairs the Apple TV once. Device build, install and launch via `xcrun devicectl`; device commands added to AGENTS.md. Run the test list on the TV; record results.

**Acceptance criteria:**
- [ ] Installs and launches on the Apple TV HD from the command line
- [ ] SPEC success criterion 1 (start < 3 s, seek/pause with remote, no ads, ≥4/5, still plays after 24 h)

**Verification:**
- [ ] Device build succeeds; human confirms on TV; results in `tasks/results.md`

**Dependencies:** Task 4, human pairing

**Files likely touched:** `AGENTS.md`, `tasks/results.md`

**Estimated scope:** S · **Skills:** shipping-and-launch

---

## Checkpoint B: MVP on device
- [ ] Task 5 criteria met; code-review-and-quality + code-simplification on Phase 1
- [ ] Human review before Phases 2–4

---

## Phase 2: 1080p

## Task 6: Verify filtered-HLS 1080p playback on the Apple TV HD

**Description:** Since T2, playback uses YouTube's HLS master filtered to H.264 ≤ 1080p (see `tasks/results.md`). On the device, play the 1080p test videos for 5 minutes each, seek, and watch the diagnostics overlay for the selected variant and dropped frames. Record the decision (HLS-first, why composition/MPVKit are not needed or are) as an ADR.

**Acceptance criteria:**
- [ ] SPEC success criterion 2 on the Apple TV HD with filtered HLS, or a documented failure that triggers T7
- [ ] ADR in `docs/adr/0001-hls-first-playback.md` with the evidence

**Verification:**
- [ ] `scripts/check.sh task`; human confirms on TV; overlay shows 1080p

**Dependencies:** Task 5

**Files likely touched:** `docs/adr/0001-hls-first-playback.md`, `tasks/results.md`

**Estimated scope:** S · **Skills:** performance-optimization, documentation-and-adrs, doubt-driven-development

---

## Task 7: (only if T6 fails) Adaptive video + audio playback

**Description:** Resolver returns an adaptive pair (best `avc1` ≤ 1080p video-only + AAC audio-only). Try `AVMutableComposition` of two remote `AVURLAsset`s first; MPVKit only after the human approves the dependency. `PlayerEngine` abstraction with filtered HLS / muxed as fallback.

**Acceptance criteria:**
- [ ] SPEC success criterion 2 on the Apple TV HD
- [ ] Pair selection covered by offline fixture tests

**Verification:**
- [ ] `scripts/check.sh task`; overlay shows 1080p on device; human confirms sync after seek

**Dependencies:** Task 6 failing

**Files likely touched:** `Sources/FooTubeCore/{StreamCandidate,YouTubeKitResolver,PlayerEngine}.swift`, `App/PlayerView.swift`, `Tests/FooTubeCoreTests/StreamSelectionTests.swift`

**Estimated scope:** M · **Skills:** source-driven-development, api-and-interface-design, test-driven-development

---

## Task 8: (only if T7 replaces AVPlayerViewController) Siri Remote controls

**Description:** If the T7 engine lacks system transport controls (e.g. MPVKit), add play/pause, scrub, ±10 s, Menu to exit for the 1st-gen Siri Remote touch surface, and fall back to AVPlayer automatically if it fails to start.

**Acceptance criteria:**
- [ ] Play/pause, scrub, skip work with the remote on the T7 engine
- [ ] A forced engine failure falls back to AVPlayer, logged

**Verification:**
- [ ] `scripts/check.sh task`; human exercises controls on TV; log shows fallback

**Dependencies:** Task 7

**Files likely touched:** `App/PlayerView.swift`, `App/PlayerControls.swift`, `Sources/FooTubeCore/PlayerEngine.swift`

**Estimated scope:** M · **Skills:** frontend-ui-engineering, debugging-and-error-recovery

---

## Checkpoint C: 1080p on device
- [ ] SPEC criterion 2; performance-optimization pass on A8 (CPU, memory, dropped frames)
- [ ] code-review-and-quality; human review

---

## Phase 3: Discovery

## Task 9: Vendor b5i/YouTubeKit as InnerTubeKit

**Description:** Copy b5i/YouTubeKit (MIT; keep LICENSE, record upstream commit) into `Packages/InnerTubeKit`, renaming package/product/target. FooTubeCore depends on it alongside alexeichhorn/YouTubeKit.

**Acceptance criteria:**
- [ ] FooTubeCore builds with both; no identity/module clash
- [ ] Network test performs one search request successfully

**Verification:**
- [ ] `scripts/check.sh task` (InnerTubeKit excluded from format; warnings-as-errors applies to our targets only)

**Dependencies:** Task 5

**Files likely touched:** `Packages/InnerTubeKit/**`, `Packages/FooTubeCore/Package.swift`, `Tests/FooTubeCoreTests/CatalogTests.swift`, `docs/adr/0002-vendor-innertubekit.md`

**Estimated scope:** S · **Skills:** doubt-driven-development, documentation-and-adrs

---

## Task 10: Search screen

**Description:** `CatalogService` wraps InnerTubeKit search with continuation. tvOS search screen with a lazy thumbnail grid (downsampled images); selecting a result plays it.

**Acceptance criteria:**
- [ ] Query shows results with thumbnail, title, channel, duration
- [ ] Reaching the end loads the next page
- [ ] Selecting a result plays it

**Verification:**
- [ ] `scripts/check.sh task` incl. fixture decoding tests; screenshots

**Dependencies:** Task 9

**Files likely touched:** `Sources/FooTubeCore/{CatalogService,Models}.swift`, `App/SearchView.swift`, `App/VideoCard.swift`

**Estimated scope:** M · **Skills:** api-and-interface-design, frontend-ui-engineering

---

## Task 11: Channel page

**Description:** Open a channel from a result or the player: header plus uploads with paging; selecting a video plays it.

**Acceptance criteria:**
- [ ] Latest uploads listed with paging
- [ ] Selecting a video plays it

**Verification:**
- [ ] `scripts/check.sh task` incl. fixture channel test; screenshot

**Dependencies:** Task 10

**Files likely touched:** `Sources/FooTubeCore/CatalogService.swift`, `App/ChannelView.swift`

**Estimated scope:** S · **Skills:** frontend-ui-engineering

---

## Checkpoint D: Discovery on device
- [ ] SPEC criterion 3 on the Apple TV HD; grid scrolling smooth on A8
- [ ] code-review-and-quality; human review

---

## Phase 4: SponsorBlock

## Task 12: SponsorBlock client in FooTubeCore

**Description:** `GET https://sponsor.ajay.app/api/skipSegments/:prefix` with the first 4 hex chars of SHA-256(videoID) (CryptoKit); filter to the requested video; categories `sponsor` (auto-skip) and `selfpromo`, `interaction`, `intro`, `outro`, `preview`, `music_offtopic`, `filler` (button).

**Acceptance criteria:**
- [ ] Returns segments (start, end, category, action) for the requested video only
- [ ] Network failure or timeout yields an empty list and never blocks playback

**Verification:**
- [ ] `scripts/check.sh task` (fixture tests for hashing/filtering) + one network test

**Dependencies:** Task 5

**Files likely touched:** `Sources/FooTubeCore/SponsorBlock.swift`, `Tests/FooTubeCoreTests/SponsorBlockTests.swift`

**Estimated scope:** S · **Skills:** test-driven-development, source-driven-development

---

## Task 13: Auto-skip `sponsor`, skip button for other categories

**Description:** Player observes time: inside a `sponsor` segment it seeks past and shows a brief notice; inside any other category it shows a focusable "Skip <category>" button.

**Acceptance criteria:**
- [ ] SPEC success criterion 4
- [ ] Seeking back into a skipped segment does not immediately re-skip

**Verification:**
- [ ] `scripts/check.sh task`; screenshot/log on a known video

**Dependencies:** Task 12, Task 3 (or Task 7/8 if that engine is current)

**Files likely touched:** `App/PlayerView.swift`, `App/SkipControls.swift`, `Sources/FooTubeCore/SkipPolicy.swift`, `Tests/FooTubeCoreTests/SkipPolicyTests.swift`

**Estimated scope:** S · **Skills:** test-driven-development, frontend-ui-engineering

---

## Phase 5: Subscriptions

## Task 14: Local subscriptions store

**Description:** Subscriptions stored on the device (`UserDefaults` JSON; SwiftData was dropped because tvOS may purge files); Subscribe/Unsubscribe on the channel page; subscriptions list screen.

**Acceptance criteria:**
- [ ] Subscribing persists across relaunch; unsubscribing removes it

**Verification:**
- [ ] `scripts/check.sh task` (in-memory container tests); relaunch check in Simulator

**Dependencies:** Task 11

**Files likely touched:** `Sources/FooTubeCore/SubscriptionStore.swift`, `App/ChannelView.swift`, `App/SubscriptionsView.swift`, `Tests/FooTubeCoreTests/SubscriptionStoreTests.swift`

**Estimated scope:** M · **Skills:** source-driven-development, test-driven-development

---

## Task 15: Subscriptions feed

**Description:** Aggregate latest uploads across subscriptions (bounded concurrent fetch, cached), newest first, as the default home section; cache shown instantly, refreshed on launch and on demand.

**Acceptance criteria:**
- [ ] SPEC success criterion 5

**Verification:**
- [ ] `scripts/check.sh task` (merge/sort/cache tests); screenshot on device

**Dependencies:** Task 14

**Files likely touched:** `Sources/FooTubeCore/FeedService.swift`, `App/HomeView.swift`, `Tests/FooTubeCoreTests/FeedServiceTests.swift`

**Estimated scope:** M · **Skills:** performance-optimization, test-driven-development

---

## Phase 6: Device feedback (owner, 2026-10-19)

Each item: acceptance = observable on device/Simulator; verification = `scripts/check.sh task` + Simulator (UI test with `XCUIRemote` where focus matters) + owner on device.

| ID | Problem (owner's words, shortened) | Acceptance | Slice |
|---|---|---|---|
| F1 | Duration badge text is black on the Apple TV (light appearance) | Badge text white on dark background in light and dark appearance | B1 |
| F2 | Subscribe button only reachable via the top-right video | From any card in the first row, pressing up focuses Subscribe | B1 |
| F3 | Members-only videos are listed (Alexandre Chappel `UCe1Aj6VEO299Yq4WkXdoD3Q`) | No members-only videos in channel pages, search, feed | B2 |
| F4 | Starts with subtitles on and an AI-dubbed audio track | Original audio track and no subtitles by default; user can still pick others | A |
| F5 | Play position not remembered | Re-opening a partly watched video resumes there (not in first 10 s / last 30 s) | A |
| F6 | Watched videos not remembered | Cards show progress bar / watched state; persists across relaunch | A (+B1 display) |
| F7 | Focused card hard to see, lift animation clipped | Focused card scales up with outline/shadow like the home screen, not clipped | B1 |
| F8 | No app icon | Layered tvOS app icon + top shelf image on the home screen | C |
| F9 | Stuck on search results; re-choosing Search should reset and focus the input | Selecting Search again clears the query and focuses the keyboard | B2 |
| F10 | Getting to a channel is awkward | Search results include channels; selecting one opens the channel | B2 |
| F11 | "Open channel" context menu: white box sticks out of the frame | Context menu preview renders cleanly with the new card style | B1 |
| F12 | Subscriptions need a sidebar to filter by channel | Sidebar: All + each channel; selection filters the feed | B2 |

## Phase 7: Device feedback round 2 (owner, 2026-10-19)

| ID | Problem | Decision / acceptance |
|---|---|---|
| G1 | New subscriptions show empty avatars until app restart | Cause (likely): `AsyncImage` loads cancelled while the Subscriptions tab is offscreen never retry. Own `RemoteImage` (URLCache + ImageIO downsampling, reloads on appear) everywhere. Avatars appear right after subscribing |
| G2 | Menu on tab bar quits the app; hard to get back to top level from a channel page; Search-reset should also apply on channel pages | HIG: tab bar stays visible, Menu pops a level, Menu at a tab's root moves focus to the tab bar, Menu on the tab bar exits (system). Returning from the tab bar into a tab pops it to its root. Per-tab navigation paths owned by RootView. Revised 2026-10-19 by owner: Search no longer clears its query on return (F9 reset dropped; it wiped searches when overshooting from the keyboard to the tab bar) |
| G3 | Black outline and scaled text look bad; want home-screen style | Apple's tvOS lockup: `.buttonStyle(.borderless)` + `.hoverEffect(.highlight)` on the thumbnail (lift, specular highlight, gimbal tilt), `.scrollClipDisabled()`. Custom CardButtonStyle removed |
| G4 | History tab | Tab listing watched / partly watched videos, newest first (history entries store the video summary) |
| G5 | Watch Later via long press | Context menu "Add to Watch Later" / "Remove from Watch Later"; Watch Later tab |
| G6 | German channels show English titles | InnerTube requests use the device language and region (hl/gl); relative ages parsed in English and German |
| G7 | Play tab redundant | Removed (and the MVP test list); `-play` launch argument stays |
| G8 | Profiles per Apple TV user | Deferred until the paid program (owner's decision) |

## Phase 9: Scrubbing thumbnails (2026-10-22)

Direction, assumptions and research: `docs/ideas/scrubbing-thumbnails.md`. Verification for every task: `scripts/check.sh task` + Simulator evidence; device checks by the owner.

| ID | Task | Acceptance |
|---|---|---|
| H1 | Spike (throwaway): check segment starts; hard-wire an I-frame playlist for one video | The 144p and 240p TS segments of 3 videos start with an IDR (NAL type 5 before any type 1). Scanning or scrubbing in the Simulator shows thumbnails. No-go → stop and ask the owner (byte ranges or storyboards) |
| H2 | Core: `HLSMasterPlaylist.filtered` offers the cheapest H.264 variant of each height ≤ 240p as an I-frame source (none if YouTube ships decodable I-frame playlists); `adding(iFramePlaylists:)` declares exactly the built ones (`iframes-<height>.m3u8`, relative; the variant's `BANDWIDTH`, video `CODECS`, `RESOLUTION`); `iFramePlaylist(fromMedia:)` turns a VOD media playlist into an `EXT-X-I-FRAMES-ONLY` playlist (same durations and URIs, version 4) | Fixture tests: sources only for low H.264 variants; only built playlists declared; rewrite keeps every segment and duration; nil for live, byte-range, fMP4, empty and non-playlist input |
| H3 | `YouTubeKitResolver` fetches the sources in parallel after the master (1 s deadline for both together, owner's choice: a slow fetch means no thumbnails, never a long start), declares what it could build; `PlaylistLoader` serves master and I-frame playlists from memory and logs I-frame requests | Simulator: thumbnails while scrubbing and scanning; live stream plays without them; start time measured (5 runs); opt-in network test: Big Buck Bunny gets both I-frame playlists |

---

## Phase 10: Sync client (2026-10-26)

Spec: `SPEC-sync-client.md`. Verification for every task: `scripts/check.sh task` plus the task's checks. One commit per task (`S<n>: …`).

| ID | Task | Acceptance |
|---|---|---|
| S1 | `SyncDocuments.swift` (four document types, `format` check, canonical encoding) and `SyncMerge.swift` (rules in the spec) | Offline tests for every rule: later `changedAt` wins, removal wins ties, canonical tie-break, pruned-elsewhere rule with/without `lastSyncAt`, 90-day pruning boundary, future timestamps, history `watched` OR, summary fallback, `clearedAt`, 500 cap, settings LWW and "never changed" loses; merge deterministic on swapped inputs |
| S2 | `SubscriptionStore`, `WatchLaterStore`, `WatchHistory`, `SkipSettingsStore` keep their public API on top of v2 documents (removals become markers, hidden from readers), expose `document()`/`replace(_:)` for sync, migrate v1 keys once and remove them | Migration tests from v1 fixtures of all four stores (order, positions, watched, summaries, settings); existing store tests pass unchanged; app builds without changes to views |
| S3 | `SyncClient`: `fetch(store)` → `(Data, ETag)?`, `put(store, data, precondition)` → `.stored(ETag)` / `.conflict(Data?, ETag?)`; typed `SyncError`; 10 s timeout; no logging of token or bodies | URLProtocol-stub tests for every Contract status; fixtures recorded from `wrangler dev` (`Fixtures/sync/`); opt-in `SyncNetworkTests` against `wrangler dev` (`FOOTUBE_SYNC_URL`/`FOOTUBE_SYNC_TOKEN`) |
| S4 | `SyncEngine` (main actor): one round per store as specified, at most 3 attempts on `412`, `lastSyncAt` in `sync.state.v1`, unsupported `format` stops that store, status per store | Engine tests with two devices (separate `UserDefaults` suites) against an in-memory fake Worker implementing the Contract: subscribe/unsubscribe/re-subscribe, concurrent edits, forced 412, device offline 100 days, newer format, 401, offline |
| S5 | `SyncConfiguration` (configuration file dropped into the app container by the run scripts — launch args `-syncURL`/`-syncToken` replaced in S5b because the system logs launch arguments — plus `-syncReset`, URL in `UserDefaults`, token in Keychain, https or localhost only); `App/SyncModel.swift` (scene phase, 5-min timer, debounced per-store changes, player close, background task) wired in `FooTubeApp`; models notify it and reload after merges; `run-sim.sh`/`run-device.sh` pass `FOOTUBE_SYNC_URL`/`FOOTUBE_SYNC_TOKEN` or `$FOOTUBE_SYNC_ENV` | Simulator with `wrangler dev`: subscribing shows a `PUT` in the Worker log within 3 s; relaunch without args keeps the configuration; `-syncReset YES` turns it off; token absent from logs (`log stream` check) |
| S6 | Settings section Sync (state row, Sync Now), descriptions; wording changes in Settings texts; `SPEC.md` and `PRODUCT.md` boundary/purpose changes from the spec; strings EN + DE | Screenshots of each state (off, synced, offline, token rejected); German strings present (`.stringsdata` keys); UI tests still pass |
| S7 | Two Simulators (`Apple TV`, `Apple TV 4K (3rd generation)`) against `wrangler dev`, then against the deployed Worker (test rows deleted afterwards); README sync section; `AGENTS.md` commands; results | Spec success criteria 1–5 shown with screenshots/logs in `tasks/results.md`; device check left to the owner |

## Phase 11: Browser inbox (after Phase 10)

Spec: `SPEC-browser-inbox.md`.

| ID | Task | Acceptance |
|---|---|---|
| I1 | Worker: `INBOX_TOKEN`, migration `0002_inbox.sql`, `POST`/`GET`/`DELETE /v1/inbox` (FooTubeSyncBackend) | Every Contract row tested, token separation, cap 100, duplicates |
| I2 | Worker: `/add` page with hash-based CSP; `npm run bookmarklet` with tested ID extraction; README | Header tests incl. CSP hash; Safari/Chrome manual check on youtube.com (no CSP violations, fragment removed) |
| I3 | Client: inbox folding in the Watch Later round; `SyncClient` inbox calls | Fake-Worker tests (new, already live, re-add after removal, two devices, failed DELETE); Simulator shows a bookmarked video first in Watch Later |

---

## Checkpoint: Complete
- [ ] SPEC success criteria 1–5 on the Apple TV HD
- [ ] code-review-and-quality, code-simplification; human sign-off
- [ ] F1–F12 verified on the Apple TV HD by the owner
