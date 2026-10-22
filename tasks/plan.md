# Implementation Plan: FooTube (private ad-free YouTube client for tvOS)

## Overview
A sideloaded tvOS app for an **Apple TV HD (A8, H.264-only, 1080p, tvOS 26)** that resolves YouTube streams on-device and plays them natively, so no ads are ever requested. Source of truth: `SPEC.md` (what), `CONSTRAINTS.md` (quality bar), this file (how/order), `tasks/todo.md` (tasks). Build order is risk-first: prove extraction on the Mac, minimal playback in the Simulator, then on the Apple TV, then 1080p, discovery, SponsorBlock, subscriptions.

## Status (2026-10-19)
All device-independent tasks (T1–T4, T9–T15) are done and verified in the `Apple TV` Simulator; see `tasks/results.md`. Phases 3–5 were built before the Checkpoint B human review because the owner asked to "go as far as possible" overnight. Open: T5 (pair + run on the Apple TV HD), T6 (1080p on device), and the device parts of Checkpoints B–D; T7/T8 only if T6 fails.

## Architecture Decisions
- **Thin app, fat core.** `FooTube` app target (SwiftUI, tvOS 18+) holds UI only. Logic lives in local package `Packages/FooTubeCore`, tested with `swift test` on the Mac. The app target links only FooTubeCore.
- **Generated project.** `project.yml` + XcodeGen; `FooTube.xcodeproj` is gitignored. `xcode-build-server` provides sourcekit-lsp support.
- **Extraction: alexeichhorn/YouTubeKit, local only** (`methods: [.local]`, no remote fallback per SPEC). Behind a `StreamResolver` protocol.
- **Format policy for Apple TV HD:** video `avc1` (H.264) only, height ≤ 1080; audio `mp4a` (AAC) preferred. Encoded once in FooTubeCore's selection rules and unit-tested.
- **Playback: `AVPlayerViewController` with a filtered HLS master** (changed after T2, see `tasks/results.md`). YouTube's visionOS client offers an HLS master for VOD and live with H.264 variants up to 1080p plus AAC audio renditions. FooTubeCore filters it to variants the Apple TV HD can decode and the app serves the filtered playlist to AVPlayer through an `AVAssetResourceLoaderDelegate`. This gives 1080p, adaptive bitrate and the system player UI from the MVP on. Muxed H.264+AAC files remain a fallback (often HTTP 403 today).
- **Phase 2 is now conditional.** Only if filtered HLS fails on the device (T6): try `AVMutableComposition` of video-only + audio-only, then MPVKit (needs approval per SPEC).
- **Catalog: b5i/YouTubeKit vendored as `Packages/InnerTubeKit`**, because both YouTubeKit packages share the SwiftPM identity, product and target name `YouTubeKit`.
- **Local data: `UserDefaults` (JSON list)** for subscriptions, changed from SwiftData after review: on tvOS only `UserDefaults` (~500 KB) is guaranteed persistent; files can be purged while the app is not running. Feed cache lives in Caches (purge is fine). No account, no sync (CloudKit needs the paid program).
- **Identifiers:** bundle `com.felixrothballer.FooTube`, team `X94768F5PD` (free; device builds expire after 7 days).

## Definition of Done (every task)
- `scripts/check.sh task` exits 0 (floor, format, secrets, core build+tests, app build with warnings as errors, dependency scan; see `CONSTRAINTS.md`).
- The changed path was exercised in the `Apple TV` Simulator (screenshot/log evidence); playback, codec and performance claims also confirmed on the Apple TV HD.
- `AGENTS.md` updated if commands, structure or conventions changed.
- One commit per task on a task branch, merged to `main` after its checkpoint (git-workflow-and-versioning).

## Skills per Phase
| When | Skill |
|---|---|
| Every task | `incremental-implementation` (thin slice, verify, commit), `test-driven-development` (failing test first for FooTubeCore logic), `context-engineering` (load only the task's spec sections and files) |
| Before using a library API (YouTubeKit, AVFoundation composition, SwiftData, MPVKit, SponsorBlock) | `source-driven-development`: read the official docs/source, cite it in the commit |
| Public FooTubeCore types (`StreamResolver`, `PlayerEngine`, `CatalogService`) | `api-and-interface-design` |
| SwiftUI screens, tvOS focus | `frontend-ui-engineering` |
| Spikes and non-obvious decisions (T2, T6, T9) | `doubt-driven-development` |
| Playback/network logging, diagnostics overlay | `observability-and-instrumentation` |
| Failures (403s, extraction breaks, A/V desync) | `debugging-and-error-recovery` |
| Each checkpoint | `code-review-and-quality`, then `code-simplification`; `performance-optimization` at Checkpoint C (A8) |
| Commits/branches | `git-workflow-and-versioning` |
| Decisions worth keeping (T6 outcome, vendoring) | `documentation-and-adrs` → `docs/adr/` |
| Device install (T5 and checkpoints) | `shipping-and-launch` (checklist, rollback = previous build) |

## Dependency Graph
```
T1 Scaffold
 └─ T2 StreamResolver spike (avc1 rules, network test)        ← Checkpoint A (fail-fast)
     └─ T3 Play by ID (AVPlayer) ── T4 Test list + diagnostics
         └─ T5 Device run                                     ← Checkpoint B (MVP)
             ├─ T6 1080p spike: AVFoundation vs MPVKit ── T7 Adaptive playback ── T8 Remote controls
             ├─ T9 Vendor InnerTubeKit ── T10 Search ── T11 Channel page ── T14 Subscriptions ── T15 Feed
             └─ T12 SponsorBlock client ── T13 Skip behaviour (on current PlayerEngine)
```
Phases 2, 3, 4 are independent after T5.

## Task List
Details in `tasks/todo.md`.

### Phase 0: Foundation
- [x] T1: Project scaffold and tooling
- [x] T2: Stream extraction spike in FooTubeCore

### Checkpoint A: Extraction viable
- [x] ≥4 of 5 non-restricted test IDs resolve to playable media (filtered HLS; see results.md) from this Mac; otherwise stop and re-plan with the human

### Phase 1: MVP playback
- [x] T3: Play a video by ID with AVPlayer
- [x] T4: Test-video list with per-video diagnostics
- [ ] T5: Deploy and run on Apple TV HD

### Checkpoint B: MVP on device (human review)
- [ ] SPEC success criterion 1 met on the Apple TV HD

### Phase 2: 1080p
- [ ] T6: Verify filtered-HLS 1080p playback on the Apple TV HD; ADR
- [ ] T7: (only if T6 fails) adaptive video+audio playback via composition, then MPVKit
- [ ] T8: (only if T7 replaces AVPlayerViewController) Siri Remote controls and engine fallback

### Checkpoint C: SPEC success criterion 2 on device

### Phase 3: Discovery
- [x] T9: Vendor b5i/YouTubeKit as InnerTubeKit
- [x] T10: Search screen
- [x] T11: Channel page

### Checkpoint D: SPEC success criterion 3 on device

### Phase 4: SponsorBlock
- [x] T12: SponsorBlock client in FooTubeCore
- [x] T13: Auto-skip `sponsor`, skip button for other categories

### Phase 5: Subscriptions
- [x] T14: Local subscriptions store
- [x] T15: Subscriptions feed

### Checkpoint: Complete
- [ ] SPEC success criteria 1–5 met on the Apple TV HD

### Phase 6: Device feedback (2026-10-19) — details in `tasks/todo.md` F1–F12
Four parallel slices with disjoint files, integrated and verified by the lead:
- **Slice A — Playback** (`HLSMasterPlaylist.swift`, new `WatchHistory.swift`, `PlayerSession.swift`, `PlaybackController.swift`, new `App/WatchHistoryModel.swift`, `FooTubeApp.swift`): F4 original audio + subtitles off, F5 resume position, F6 watched history.
- **Slice B1 — Cards & channel page** (`VideoGrid.swift`, `ChannelView.swift`): F1 duration badge color, F7 focus effect, F11 context menu look, F2 subscribe button reachable, plus watch progress on cards (reads Slice A's `WatchHistoryModel`).
- **Slice B2 — Search & subscriptions** (`Catalog.swift`, `SearchView.swift`, `SubscriptionsView.swift`, `RootView.swift`): F3 hide members-only, F9 search reset, F10 channels in search, F12 sidebar.
- **Slice C — App icon** (`App/Assets.xcassets`, `project.yml`, `scripts/make-icon.swift`): F8.
- **Lead:** integration, `scripts/check.sh task`, Simulator verification incl. a UI test target driving the Siri Remote (`XCUIRemote`) for focus behaviour (F2, F7, F9), then device install.
- [x] F1–F12 done and verified in the Simulator (device check by owner pending)

### Phase 7: Device feedback round 2 (2026-10-19) — details in `tasks/todo.md` G1–G8
Research done first (HIG tab bars, Apple's tvOS media-catalog sample, User Management docs). Slices:
- **Core** (`Catalog.swift`, `Feed.swift`, `WatchHistory.swift`, new `WatchLater.swift`, tests): G6 device-language titles + German relative ages, G4/G5 stores.
- **UI** (`VideoGrid.swift`, `ChannelView.swift`, `SearchView.swift`, `SubscriptionsView.swift`, new `RemoteImage.swift`, `WatchLaterModel.swift`, `WatchLaterView.swift`, `HistoryView.swift`, `WatchHistoryModel.swift`): G1, G3, G4/G5 screens + context menu.
- **Lead** (`RootView.swift`, `FooTubeApp.swift`, `PlaybackController.swift`, `PlayerSession.swift`, removal of `HomeView.swift`/`TestVideos.swift`, UI tests): G2, G7, integration.
- Deferred: per-Apple-TV-user data (needs paid program: Personal Teams can't sign User Management — verified), iPhone/iPad + sync (estimate given to owner).
- [x] G1–G7 done and verified in the Simulator (G8 deferred)

### Phase 8: Chapters, search suggestions, Up next (2026-10-19, local only, no device install)
From the library-capabilities idea list (owner picked 1–3). InnerTubeKit `MoreVideoInfosResponse` (watch page: chapters, channel, related videos) and `AutoCompletionResponse`; no vendored changes.
- **Core** (`Catalog.swift`): `Catalog.details(_:)` → `VideoDetails` (chapters ordered/deduped, channel ID, related videos), `VideoDetails.upNext(after:isWatched:)` (skips current, watched, live; same channel first), `Catalog.suggestions(_:)`. Unit tests `VideoDetailsTests`, network tests in `CatalogNetworkTests`.
- **Player** (`PlayerSession.swift`, `PlayerView.swift`, `RootView.swift`, `PlaybackController.swift`): chapters as `AVPlayerItem.navigationMarkerGroups` (titles, then thumbnails); Up next as the system content proposal (`AVContentProposal` + own `UpNextViewController`, 10 s countdown, Play Now / Close, Menu closes); one player cover across videos.
- **Search** (`SearchView.swift`): `.searchSuggestions` row under the keyboard.
- [x] Verified in the Simulator (chapter row with thumbnails, Up next countdown + autoplay, suggestions); device check by owner pending

### Phase 9: Scrubbing thumbnails (2026-10-22) — details in `tasks/todo.md` H1–H3
Direction and assumptions: `docs/ideas/scrubbing-thumbnails.md`. AVKit draws scrubbing and scanning thumbnails only from I-frame playlists; YouTube's HLS has none. FooTube declares I-frame variants for the 144p and 240p H.264 variants and serves them lazily from `PlaylistLoader`, rewritten from the googlevideo media playlists (one whole TS segment per entry).
- [ ] H1: Spike: segments start with an IDR; AVKit shows thumbnails from whole-segment I-frame entries (Simulator). No-go → back to the owner (byte ranges or storyboards)
- [ ] H2: Core: I-frame lines in `HLSMasterPlaylist.filtered`, I-frame media-playlist rewrite, fixture tests
- [ ] H3: App: lazy serving in `PlaylistLoader`, request logging, Simulator evidence, start-time comparison
- [ ] Owner on the Apple TV HD: thumbnails while scrubbing, start time unchanged, scrubbing smooth

## Risks and Mitigations
| Risk | Impact | Mitigation |
|---|---|---|
| YouTube changes break extraction / PO-token enforcement expands | High | T2 fail-fast gate; `StreamResolver` abstraction; yt-dlp cross-check; remote fallback or Yattee Server only with approval |
| No HLS offered for some videos (e.g. made-for-kids: YouTubeKit gets 0 streams) | Med | Clear error; muxed fallback; investigate YouTubeKit request differences vs yt-dlp `visionos` client if it matters |
| Filtered HLS stutters or misbehaves on the A8 | Med | T6 on device; then composition/MPVKit (Phase 2 conditional tasks) |
| YouTube stops offering HLS to the visionOS client | High | Muxed fallback; Phase 2 conditional tasks; monitor with the network test |
| Stream URLs need client-matching headers | Med | T3 checks for 403 at playback; pass headers via asset options |
| Simulator decodes with Mac hardware | Med | Device verification at T5 and every checkpoint |
| A8 UI performance (thumbnail grids) | Med | Downsampled thumbnails, lazy grids; measured at Checkpoint D |
| Free Personal Team: 7-day expiry, App ID limit | Low | Fixed bundle ID; weekly rebuild |

## Open Questions
- None blocking. Device tvOS is 26 per owner (Apple skipped 19–25).
