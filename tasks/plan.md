# Implementation Plan: FooTube (private ad-free YouTube client for tvOS)

## Overview
A sideloaded tvOS app for an **Apple TV HD (A8, H.264-only, 1080p, tvOS 26)** that resolves YouTube streams on-device and plays them natively, so no ads are ever requested. Source of truth: `SPEC.md` (what), `CONSTRAINTS.md` (quality bar), this file (how/order), `tasks/todo.md` (tasks). Build order is risk-first: prove extraction on the Mac, minimal playback in the Simulator, then on the Apple TV, then 1080p, discovery, SponsorBlock, subscriptions.

## Architecture Decisions
- **Thin app, fat core.** `FooTube` app target (SwiftUI, tvOS 18+) holds UI only. Logic lives in local package `Packages/FooTubeCore`, tested with `swift test` on the Mac. The app target links only FooTubeCore.
- **Generated project.** `project.yml` + XcodeGen; `FooTube.xcodeproj` is gitignored. `xcode-build-server` provides sourcekit-lsp support.
- **Extraction: alexeichhorn/YouTubeKit, local only** (`methods: [.local]`, no remote fallback per SPEC). Behind a `StreamResolver` protocol.
- **Format policy for Apple TV HD:** video `avc1` (H.264) only, height ≤ 1080; audio `mp4a` (AAC) preferred. Encoded once in FooTubeCore's selection rules and unit-tested.
- **Playback v1: `AVPlayerViewController`** with a muxed `avc1` stream (likely 360p, maybe 720p).
- **Playback v2 (1080p): decided by spike T6.** YouTube serves 1080p only as separate video-only + audio-only streams. Try AVFoundation first (an `AVMutableComposition` from two remote `AVURLAsset`s, or a locally generated HLS playlist over byte ranges); add MPVKit only if both fail (dependency needs approval per SPEC). Rationale: on H.264-only hardware MPVKit's VP9/AV1 advantage is irrelevant, and AVFoundation keeps the system player UI and the smallest binary.
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
- [ ] T6: Spike: combine separate video + audio streams (AVFoundation first, MPVKit fallback)
- [ ] T7: 1080p adaptive playback via the chosen engine
- [ ] T8: Siri Remote controls and engine fallback

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
| No muxed `avc1` stream for some videos | Med | Error shown clearly in MVP; Phase 2 adaptive playback covers it |
| AVFoundation cannot combine remote fMP4 video + audio | Med | T6 tries composition and local HLS; MPVKit (with approval) as fallback |
| MPVKit too heavy for A8 / 2 GB | Med | Only if T6 needs it; hardware decode via VideoToolbox; measure on device at Checkpoint C |
| Stream URLs need client-matching headers | Med | T3 checks for 403 at playback; pass headers via asset options |
| Simulator decodes with Mac hardware | Med | Device verification at T5 and every checkpoint |
| A8 UI performance (thumbnail grids) | Med | Downsampled thumbnails, lazy grids; measured at Checkpoint D |
| Free Personal Team: 7-day expiry, App ID limit | Low | Fixed bundle ID; weekly rebuild |

## Open Questions
- None blocking. Device tvOS is 26 per owner (Apple skipped 19–25).
