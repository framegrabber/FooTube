# Implementation Plan: FooTube (private ad-free YouTube client for tvOS)

## Overview
A sideloaded tvOS app that resolves YouTube streams on-device and plays them without the official web player, so no ads are ever requested. Build order is risk-first: prove stream extraction on this Mac, then minimal playback in the Simulator, then on the real Apple TV, then add quality (MPVKit), discovery (search/channels), SponsorBlock, and local subscriptions. Background research: `tvos-youtube-client-findings.md`.

## Architecture Decisions
- **Thin app, fat core.** `FooTube` app target (SwiftUI, tvOS 18+) holds UI only. All logic lives in a local Swift package `Packages/FooTubeCore`, testable with `swift test` on the Mac without the Simulator, and natively understood by sourcekit-lsp.
- **Project file is generated.** `project.yml` + XcodeGen; `FooTube.xcodeproj` is gitignored and never hand-edited. `xcode-build-server` writes `buildServer.json` so sourcekit-lsp understands the app target.
- **Stream extraction: alexeichhorn/YouTubeKit** (MIT, tvOS 13+, clients incl. `ANDROID_VR`, `VISIONOS`, TV embedded). Wrapped behind a `StreamResolver` protocol in FooTubeCore so it can be swapped (remote fallback, Yattee Server) without touching UI.
- **Catalog (search/channels): b5i/YouTubeKit, vendored and renamed** to `Packages/InnerTubeKit`. Both upstream packages use package, product, and target name `YouTubeKit`, and both derive SwiftPM identity `youtubekit`; `moduleAliases` does not resolve the identity clash. A local path package with renamed target avoids both. Deferred to Phase 3.
- **Playback v1: `AVPlayerViewController`** with a muxed (audio+video) stream: free Siri Remote handling and system UI. Expect 360p–720p.
- **Playback v2: MPVKit** for separate video-only + audio-only adaptive streams (1080p+, VP9/AV1). Behind a `PlayerEngine` abstraction so AVPlayer remains a fallback.
- **Local data: SwiftData** (subscriptions, watch history). No Google account login.
- **Identifiers:** bundle ID `com.felixrothballer.FooTube` (fixed once: free accounts get few App IDs per week), Team `X94768F5PD` (free Personal Team; device builds expire after 7 days).

## Definition of Done (every task)
- `swift build` and `swift test` pass in `Packages/FooTubeCore` (network tests opt-in, see AGENTS.md).
- `xcodebuild` Simulator build succeeds with no new warnings.
- The changed path was exercised in the Simulator (screenshot or log evidence); device-relevant tasks also on the Apple TV.
- `AGENTS.md` updated if commands, structure, or conventions changed.

## Dependency Graph
```
T1 Scaffold (project.yml, FooTubeCore, AGENTS.md, LSP)
 └─ T2 StreamResolver spike (YouTubeKit, network test)      ← fail-fast gate
     └─ T3 Play by ID (AVPlayer) ── T4 Test list + diagnostics
         └─ T5 Device run (needs pairing)                    ← MVP gate
             ├─ T6 MPVKit render spike ── T7 Adaptive streams ── T8 Remote controls
             ├─ T9 Vendor InnerTubeKit ── T10 Search ── T11 Channel page
             │                                         └─ T14 Subscriptions store ── T15 Feed
             └─ T12 SponsorBlock client ── T13 Auto-skip (needs a PlayerEngine: T3 or T8)
```
Phases 2, 3 and 4 are independent after T5 and can run in parallel; T13 targets whichever player engine is current.

## Task List
Detailed tasks with acceptance criteria and verification: `tasks/todo.md`.

### Phase 0: Foundation
- [ ] T1: Project scaffold and tooling
- [ ] T2: Stream extraction spike in FooTubeCore

### Checkpoint A: Extraction viable
- [ ] ≥4 of 5 non-restricted test IDs resolve to a playable muxed stream from this Mac
- [ ] If not: stop, re-plan around remote fallback or Yattee Server before any UI work

### Phase 1: MVP playback (Simulator → device)
- [ ] T3: Play a video by ID with AVPlayer
- [ ] T4: Test-video list with per-video diagnostics
- [ ] T5: Deploy and run on Apple TV

### Checkpoint B: MVP on device (human review)
- [ ] MVP pass criteria met on the Apple TV (see T5)

### Phase 2: Quality (MPVKit)
- [ ] T6: MPVKit render spike on tvOS
- [ ] T7: Play separate video-only + audio-only streams
- [ ] T8: Siri Remote controls and engine fallback

### Checkpoint C: 1080p playback on device

### Phase 3: Discovery
- [ ] T9: Vendor b5i/YouTubeKit as InnerTubeKit
- [ ] T10: Search screen
- [ ] T11: Channel page

### Checkpoint D: Search → play end-to-end on device

### Phase 4: SponsorBlock
- [ ] T12: SponsorBlock client in FooTubeCore
- [ ] T13: Auto-skip segments during playback

### Phase 5: Subscriptions
- [ ] T14: Local subscriptions store
- [ ] T15: Subscriptions feed

### Checkpoint: Complete
- [ ] All acceptance criteria met on device
- [ ] Ready for daily use

## Risks and Mitigations
| Risk | Impact | Mitigation |
|---|---|---|
| YouTube changes break extraction / PO-token enforcement expands | High | T2 is a fail-fast gate; `StreamResolver` abstraction; YouTubeKit `.remote` fallback; Yattee Server as last resort |
| Muxed streams capped at 360p or missing for some videos | Med | Accept for MVP; Phase 2 MPVKit with adaptive streams |
| Stream URLs need client-matching headers (User-Agent) for playback | Med | T3 checks for 403 on playback; pass headers via `AVURLAsset` options or mpv `http-header-fields` |
| MPVKit tvOS rendering (Metal/OpenGL layer) is hard to integrate | High | T6 isolated spike before T7; Yattee 2 source (AGPL, MPVKit on tvOS) as reference; AVPlayer stays as fallback |
| Simulator decodes with Mac hardware; formats differ on device | Med | T5 and every checkpoint verified on the real Apple TV |
| Package name/identity clash between the two YouTubeKits | Med | Vendor b5i as `InnerTubeKit` (T9) |
| Free Personal Team: 7-day expiry, App ID limits | Low | Fixed bundle ID; rebuild weekly; consider paid program if it gets annoying |
| ToS / account bans | Low | No Google login; requests from home IP only |

## Open Questions
- Which Apple TV model and tvOS version is the target device? (Affects AV1/HDR decisions in Phase 2 and the deployment target.)
- Remote fallback: use the package author's hosted server (sees video IDs), self-host YouTubeKit-Server, or no fallback?
- SponsorBlock: which categories auto-skip vs. show a skip button?
- Subscriptions: start empty, or import from a Google Takeout `subscriptions.csv`?
