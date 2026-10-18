# Implementation Plan: FooTube (private ad-free YouTube client for tvOS)

## Overview
A sideloaded tvOS app for an **Apple TV HD (A8, H.264-only, 1080p, tvOS 26)** that resolves YouTube streams on-device and plays them natively, so no ads are ever requested. Source of truth: `SPEC.md` (what), `CONSTRAINTS.md` (quality bar), this file (how/order), `tasks/todo.md` (tasks). Build order is risk-first: prove extraction on the Mac, minimal playback in the Simulator, then on the Apple TV, then 1080p, discovery, SponsorBlock, subscriptions.

## Architecture Decisions
- **Thin app, fat core.** `FooTube` app target (SwiftUI, tvOS 18+) holds UI only. Logic lives in local package `Packages/FooTubeCore`, tested with `swift test` on the Mac. The app target links only FooTubeCore.
- **Generated project.** `project.yml` + XcodeGen; `FooTube.xcodeproj` is gitignored. `xcode-build-server` provides sourcekit-lsp support.
- **Extraction: alexeichhorn/YouTubeKit, local only** (`methods: [.local]`, no remote fallback per SPEC). Behind a `StreamResolver` protocol.
- **Format policy for Apple TV HD:** video `avc1` (H.264) only, height ≤ 1080; audio `mp4a` (AAC) preferred. Encoded once in FooTubeCore's selection rules and unit-tested.
- **Playback: `AVPlayerViewController` with a filtered HLS master** (changed after T2, see `tasks/results.md`). YouTube's visionOS client offers an HLS master for VOD and live with H.264 variants up to 1080p plus AAC audio renditions. FooTubeCore filters it to variants the Apple TV HD can decode and the app serves the filtered playlist to AVPlayer through an `AVAssetResourceLoaderDelegate`. This gives 1080p, adaptive bitrate and the system player UI from the MVP on. Muxed H.264+AAC files remain a fallback (often HTTP 403 today).
- **Phase 2 is now conditional.** Only if filtered HLS fails on the device (T6): try `AVMutableComposition` of video-only + audio-only, then MPVKit (needs approval per SPEC).
- **Catalog: b5i/YouTubeKit vendored as `Packages/InnerTubeKit`**, because both YouTubeKit packages share the SwiftPM identity, product and target name `YouTubeKit`.
- **Local data: SwiftData**, no account, no sync (sync is out of scope: CloudKit needs the paid program).
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
- [ ] T1: Project scaffold and tooling
- [ ] T2: Stream extraction spike in FooTubeCore

### Checkpoint A: Extraction viable
- [ ] ≥4 of 5 non-restricted test IDs resolve to a playable muxed `avc1` stream from this Mac; otherwise stop and re-plan with the human

### Phase 1: MVP playback
- [ ] T3: Play a video by ID with AVPlayer
- [ ] T4: Test-video list with per-video diagnostics
- [ ] T5: Deploy and run on Apple TV HD

### Checkpoint B: MVP on device (human review)
- [ ] SPEC success criterion 1 met on the Apple TV HD

### Phase 2: 1080p
- [ ] T6: Verify filtered-HLS 1080p playback on the Apple TV HD; ADR
- [ ] T7: (only if T6 fails) adaptive video+audio playback via composition, then MPVKit
- [ ] T8: (only if T7 replaces AVPlayerViewController) Siri Remote controls and engine fallback

### Checkpoint C: SPEC success criterion 2 on device

### Phase 3: Discovery
- [ ] T9: Vendor b5i/YouTubeKit as InnerTubeKit
- [ ] T10: Search screen
- [ ] T11: Channel page

### Checkpoint D: SPEC success criterion 3 on device

### Phase 4: SponsorBlock
- [ ] T12: SponsorBlock client in FooTubeCore
- [ ] T13: Auto-skip `sponsor`, skip button for other categories

### Phase 5: Subscriptions
- [ ] T14: Local subscriptions store
- [ ] T15: Subscriptions feed

### Checkpoint: Complete
- [ ] SPEC success criteria 1–5 met on the Apple TV HD

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
