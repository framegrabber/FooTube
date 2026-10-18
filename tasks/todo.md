# FooTube Task List

Commands referenced below (canonical copies will live in `AGENTS.md` after T1):
- Core tests: `swift test --package-path Packages/FooTubeCore`
- Network tests: `FOOTUBE_NETWORK_TESTS=1 swift test --package-path Packages/FooTubeCore`
- Generate project: `xcodegen generate`
- Simulator build: `xcodebuild -project FooTube.xcodeproj -scheme FooTube -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build | xcbeautify`
- Screenshot: `xcrun simctl io booted screenshot <path>`

---

## Phase 0: Foundation

## Task 1: Project scaffold and tooling

**Description:** Create the repo structure: XcodeGen `project.yml` for a tvOS 18 SwiftUI app `FooTube` (bundle `com.felixrothballer.FooTube`, team `X94768F5PD`, automatic signing), a local Swift package `Packages/FooTubeCore` (library + test target), `.gitignore` (xcodeproj, DerivedData, build, buildServer.json, .DS_Store), and `AGENTS.md` with build/test/run commands, layout, and conventions. Configure `xcode-build-server` for sourcekit-lsp. App shows a placeholder screen.

**Acceptance criteria:**
- [ ] `xcodegen generate` produces a project that builds for the tvOS Simulator
- [ ] App launches in the Simulator and shows the placeholder screen
- [ ] LSP resolves a symbol from FooTubeCore inside the app target

**Verification:**
- [ ] Tests pass: `swift test --package-path Packages/FooTubeCore`
- [ ] Build succeeds: Simulator build command
- [ ] Manual check: Simulator screenshot shows placeholder; `lsp definition` on a FooTubeCore symbol from app code succeeds

**Dependencies:** None

**Files likely touched:**
- `project.yml`, `.gitignore`, `AGENTS.md`
- `App/FooTubeApp.swift`
- `Packages/FooTubeCore/Package.swift`, `Packages/FooTubeCore/Sources/FooTubeCore/*.swift`, `Packages/FooTubeCore/Tests/FooTubeCoreTests/*.swift`

**Estimated scope:** M

---

## Task 2: Stream extraction spike in FooTubeCore

**Description:** Add alexeichhorn/YouTubeKit to FooTubeCore. Define `StreamResolver` (video ID → `ResolvedStream` with URL, resolution, container, source client, isMuxed) and a `YouTubeKitResolver` that picks the best natively playable muxed stream. Add an opt-in network test over 5 fixed IDs (normal, label music video, kids, long, livestream). Cross-check the same IDs with `yt-dlp --extractor-args "youtube:player_client=android_vr" -F`. This is the fail-fast gate.

**Acceptance criteria:**
- [ ] ≥4 of 5 non-restricted IDs resolve to a URL whose first bytes download with HTTP 200/206
- [ ] Resolution and failure reasons per ID are printed by the test
- [ ] Resolver selection logic is covered by an offline unit test using fixture stream lists

**Verification:**
- [ ] Tests pass: `swift test --package-path Packages/FooTubeCore` (offline) and with `FOOTUBE_NETWORK_TESTS=1`
- [ ] Build succeeds: Simulator build command
- [ ] Manual check: results table recorded in `tasks/results.md`, compared with yt-dlp output

**Dependencies:** Task 1

**Files likely touched:**
- `Packages/FooTubeCore/Package.swift`
- `Packages/FooTubeCore/Sources/FooTubeCore/StreamResolver.swift`
- `Packages/FooTubeCore/Sources/FooTubeCore/YouTubeKitResolver.swift`
- `Packages/FooTubeCore/Tests/FooTubeCoreTests/StreamResolverTests.swift`
- `tasks/results.md`

**Estimated scope:** M

---

## Checkpoint A: Extraction viable
- [ ] Offline and network tests pass
- [ ] ≥4/5 IDs resolve; otherwise stop and re-plan (remote fallback / Yattee Server) with the human

---

## Phase 1: MVP playback

## Task 3: Play a video by ID with AVPlayer

**Description:** A single screen with a text field (video ID or YouTube URL, parsed in FooTubeCore) and a Play button. Resolves via `StreamResolver` and presents `AVPlayerViewController`. Loading and error states visible; errors include source client and reason.

**Acceptance criteria:**
- [ ] Entering a known-good ID plays video with audio in the Simulator
- [ ] Full URLs (`watch?v=`, `youtu.be/`, `shorts/`) and bare IDs are accepted
- [ ] A failing ID shows an error message instead of a blank player

**Verification:**
- [ ] Tests pass: core tests incl. URL/ID parsing cases
- [ ] Build succeeds: Simulator build command
- [ ] Manual check: two Simulator screenshots a few seconds apart show different video frames; no ad shown

**Dependencies:** Task 2

**Files likely touched:**
- `App/PlayByIDView.swift`, `App/PlayerView.swift`
- `Packages/FooTubeCore/Sources/FooTubeCore/VideoID.swift`
- `Packages/FooTubeCore/Tests/FooTubeCoreTests/VideoIDTests.swift`

**Estimated scope:** M

---

## Task 4: Test-video list with per-video diagnostics

**Description:** Home screen lists the 7 MVP test cases (normal, music video, age-restricted, kids, livestream, >1h, Short) plus the free-text entry. Each row plays the video; a small overlay in the player shows source client, resolution, container, and time to first frame.

**Acceptance criteria:**
- [ ] All 7 entries are selectable with the Siri Remote and start playback or show an error
- [ ] Overlay shows client, resolution, and time-to-first-frame for playing videos

**Verification:**
- [ ] Tests pass: core tests
- [ ] Build succeeds: Simulator build command
- [ ] Manual check: screenshot of the list and of the overlay during playback

**Dependencies:** Task 3

**Files likely touched:**
- `App/HomeView.swift`, `App/DiagnosticsOverlay.swift`
- `Packages/FooTubeCore/Sources/FooTubeCore/TestVideos.swift`

**Estimated scope:** S

---

## Task 5: Deploy and run on Apple TV

**Description:** Human pairs the Apple TV once. Build for the device, install and launch via `xcrun devicectl`, add the device commands to AGENTS.md, and run the test list on the TV. Record results.

**Acceptance criteria:**
- [ ] App installs and launches on the Apple TV from the command line
- [ ] Playback starts in < ~3 s, seek and pause/resume work with the Siri Remote, no ads
- [ ] ≥4 of 5 non-restricted cases play; the same video still plays 24 h later

**Verification:**
- [ ] Build succeeds: device build (`-destination 'platform=tvOS,id=<udid>'`)
- [ ] Manual check: human confirms on TV; results appended to `tasks/results.md`

**Dependencies:** Task 4, human pairing

**Files likely touched:**
- `AGENTS.md`, `tasks/results.md`

**Estimated scope:** S

---

## Checkpoint B: MVP on device
- [ ] Task 5 criteria met
- [ ] Review with human before Phase 2–4 (answer open questions in plan.md)

---

## Phase 2: Quality (MPVKit)

## Task 6: MPVKit render spike on tvOS

**Description:** Add MPVKit and a minimal `MPVPlayerView` (UIViewRepresentable) that renders a single muxed stream URL on tvOS. Use Yattee 2's MPVKit integration as reference. Isolated from the main player path.

**Acceptance criteria:**
- [ ] A muxed stream renders with audio via mpv in the Simulator and on the Apple TV
- [ ] No crash when opening/closing the player 5 times in a row

**Verification:**
- [ ] Build succeeds: Simulator and device builds
- [ ] Manual check: screenshots show moving frames; human confirms on TV

**Dependencies:** Task 5

**Files likely touched:**
- `project.yml` or `Packages/FooTubeCore/Package.swift` (MPVKit dependency)
- `App/MPV/MPVPlayerView.swift`, `App/MPV/MPVController.swift`

**Estimated scope:** M

---

## Task 7: Play separate video-only + audio-only streams

**Description:** Extend the resolver to return an adaptive pair (best video-only within device capability + best audio-only). Introduce a `PlayerEngine` abstraction; the mpv engine plays the video URL with the audio URL as an external audio track.

**Acceptance criteria:**
- [ ] A 1080p video plays at 1080p with audio in sync on the Apple TV
- [ ] Resolver pair selection is covered by offline fixture tests (codec/resolution caps)

**Verification:**
- [ ] Tests pass: core tests
- [ ] Build succeeds: Simulator and device builds
- [ ] Manual check: diagnostics overlay shows 1080p; human confirms A/V sync after a seek

**Dependencies:** Task 6

**Files likely touched:**
- `Packages/FooTubeCore/Sources/FooTubeCore/StreamResolver.swift`, `YouTubeKitResolver.swift`, `PlayerEngine.swift`
- `App/MPV/MPVController.swift`
- `Packages/FooTubeCore/Tests/FooTubeCoreTests/StreamResolverTests.swift`

**Estimated scope:** M

---

## Task 8: Siri Remote controls and engine fallback

**Description:** Custom transport controls for the mpv player (play/pause, scrub, ±10 s, menu to exit) and automatic fallback to the AVPlayer engine with a muxed stream if mpv fails to start.

**Acceptance criteria:**
- [ ] Play/pause, scrub and skip work with the Siri Remote on the mpv engine
- [ ] Forcing an mpv failure falls back to AVPlayer and playback continues

**Verification:**
- [ ] Build succeeds: Simulator and device builds
- [ ] Manual check: human exercises controls on TV; log shows fallback path

**Dependencies:** Task 7

**Files likely touched:**
- `App/MPV/MPVControlsView.swift`, `App/PlayerView.swift`
- `Packages/FooTubeCore/Sources/FooTubeCore/PlayerEngine.swift`

**Estimated scope:** M

---

## Checkpoint C: 1080p playback on device
- [ ] Test list plays via mpv at ≥1080p where available; fallback works
- [ ] Review with human

---

## Phase 3: Discovery

## Task 9: Vendor b5i/YouTubeKit as InnerTubeKit

**Description:** Copy b5i/YouTubeKit (MIT, keep LICENSE and upstream commit hash) into `Packages/InnerTubeKit` with package/product/target renamed to `InnerTubeKit`. Depend on it from FooTubeCore alongside alexeichhorn/YouTubeKit.

**Acceptance criteria:**
- [ ] FooTubeCore builds with both packages; no identity or module clashes
- [ ] A network test performs one `SearchResponse` request successfully

**Verification:**
- [ ] Tests pass: core tests (offline + network)
- [ ] Build succeeds: Simulator build command

**Dependencies:** Task 5

**Files likely touched:**
- `Packages/InnerTubeKit/**` (vendored), `Packages/FooTubeCore/Package.swift`
- `Packages/FooTubeCore/Tests/FooTubeCoreTests/CatalogTests.swift`

**Estimated scope:** S (vendored code excluded)

---

## Task 10: Search screen

**Description:** `CatalogService` in FooTubeCore wraps InnerTubeKit search (+ continuation). tvOS search screen (system keyboard / `.searchable`) shows a thumbnail grid; selecting a result plays it through the current player engine.

**Acceptance criteria:**
- [ ] Typing a query shows results with thumbnails, title, channel, duration
- [ ] Scrolling to the end loads the next page
- [ ] Selecting a result plays it

**Verification:**
- [ ] Tests pass: core tests incl. decoding from a fixture search response
- [ ] Build succeeds: Simulator build command
- [ ] Manual check: screenshots of results and playback from a result

**Dependencies:** Task 9

**Files likely touched:**
- `Packages/FooTubeCore/Sources/FooTubeCore/CatalogService.swift`, `Models.swift`
- `App/SearchView.swift`, `App/VideoCard.swift`

**Estimated scope:** M

---

## Task 11: Channel page

**Description:** From a search result or player, open the channel: header plus videos tab with continuation. Selecting a video plays it.

**Acceptance criteria:**
- [ ] Channel page lists the latest uploads with paging
- [ ] Selecting a video plays it

**Verification:**
- [ ] Tests pass: core tests incl. fixture channel response
- [ ] Build succeeds: Simulator build command
- [ ] Manual check: screenshot of a channel page

**Dependencies:** Task 10

**Files likely touched:**
- `Packages/FooTubeCore/Sources/FooTubeCore/CatalogService.swift`
- `App/ChannelView.swift`

**Estimated scope:** S

---

## Checkpoint D: Search → play end-to-end on device
- [ ] Search, channel, and playback work on the Apple TV
- [ ] Review with human

---

## Phase 4: SponsorBlock

## Task 12: SponsorBlock client in FooTubeCore

**Description:** Client for `GET /api/skipSegments/:sha256HashPrefix` (4-char prefix of SHA-256 of the video ID, CryptoKit), filtering the response to the requested video and configured categories.

**Acceptance criteria:**
- [ ] Returns segments (start, end, category) for the requested video only
- [ ] Network failure yields an empty list, never blocks playback

**Verification:**
- [ ] Tests pass: offline fixture tests (hash prefix, filtering) + one network test

**Dependencies:** Task 5

**Files likely touched:**
- `Packages/FooTubeCore/Sources/FooTubeCore/SponsorBlock.swift`
- `Packages/FooTubeCore/Tests/FooTubeCoreTests/SponsorBlockTests.swift`

**Estimated scope:** S

---

## Task 13: Auto-skip segments during playback

**Description:** Player observes time and skips configured segments, showing a brief "Skipped sponsor" notice. Works on the current `PlayerEngine`.

**Acceptance criteria:**
- [ ] Playback jumps over a known sponsor segment and shows the notice
- [ ] Manual seek back into a segment is not immediately re-skipped

**Verification:**
- [ ] Build succeeds: Simulator build command
- [ ] Manual check: log/screenshot of the skip on a known video

**Dependencies:** Task 12, Task 3 (or Task 8 if mpv is current)

**Files likely touched:**
- `App/PlayerView.swift`, `App/SkipNotice.swift`
- `Packages/FooTubeCore/Sources/FooTubeCore/PlayerEngine.swift`

**Estimated scope:** S

---

## Phase 5: Subscriptions

## Task 14: Local subscriptions store

**Description:** SwiftData model for subscribed channels; subscribe/unsubscribe button on the channel page; subscriptions list screen.

**Acceptance criteria:**
- [ ] Subscribing persists across app relaunch
- [ ] Unsubscribing removes the channel from the list

**Verification:**
- [ ] Tests pass: store tests with an in-memory container
- [ ] Build succeeds: Simulator build command
- [ ] Manual check: relaunch Simulator app; list persists

**Dependencies:** Task 11

**Files likely touched:**
- `Packages/FooTubeCore/Sources/FooTubeCore/SubscriptionStore.swift`
- `App/ChannelView.swift`, `App/SubscriptionsView.swift`

**Estimated scope:** M

---

## Task 15: Subscriptions feed

**Description:** Aggregate the latest uploads of all subscribed channels (concurrent fetch, cached, refreshed on launch and on demand), newest first, as the default home section.

**Acceptance criteria:**
- [ ] Feed shows recent uploads across subscriptions sorted by date
- [ ] Cached feed displays instantly on relaunch, then refreshes

**Verification:**
- [ ] Tests pass: merge/sort/cache tests with fixtures
- [ ] Build succeeds: Simulator build command
- [ ] Manual check: screenshot of feed on device

**Dependencies:** Task 14

**Files likely touched:**
- `Packages/FooTubeCore/Sources/FooTubeCore/FeedService.swift`
- `App/HomeView.swift`

**Estimated scope:** M

---

## Checkpoint: Complete
- [ ] All tests pass, builds clean
- [ ] All flows verified on the Apple TV
- [ ] Human sign-off
