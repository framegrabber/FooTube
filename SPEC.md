# Spec: FooTube

## Objective
A private, sideloaded tvOS app for one household that plays YouTube videos without ads on an **Apple TV HD (4th generation, 2015, A8)**. Streams are resolved on the device and played natively, so the official web player and its ad requests are never involved. Background research: `tvos-youtube-client-findings.md`.

**User:** the owner, using the Siri Remote on a 1080p TV. Not distributed, no App Store.

**User stories (in build order):**
1. As the user, I enter a video ID or YouTube URL and it plays with sound, without ads.
2. As the user, I play videos at up to 1080p with smooth playback on my Apple TV HD.
3. As the user, I search YouTube and play a result; I open a channel and browse its uploads.
4. As the user, sponsor segments are skipped automatically; other SponsorBlock segments show a skip button.
5. As the user, I subscribe to channels (stored only on the device) and see a feed of their latest uploads.
6. As the user, I find videos I watched in a History tab and save videos for later (long press → Watch Later) in a Watch Later tab; playback resumes where I stopped.

## Target Hardware Constraints
Source: [Apple TV HD technical specifications](https://support.apple.com/en-us/111928), [tvOS 27 drops Apple TV HD](https://www.macrumors.com/2026/09/14/tvos-27-drops-support-for-two-apple-tv-models).
- **Video decode:** H.264 only, up to 1080p 60 fps, High/Main Profile level 4.2. No HEVC, VP9, or AV1 hardware decode → select `avc1` video formats only, max 1080p.
- **Audio:** AAC (`mp4a`) preferred; Opus requires software decode.
- **OS ceiling:** tvOS 26 is the last release for this device. Deployment target tvOS 18.
- **Performance:** A8 CPU and 2 GB RAM; no software video decoding at 1080p; keep the UI light (thumbnail grids must scroll smoothly).
- **Remote:** Siri Remote (1st gen) touch surface: swipe, click, Menu, Play/Pause.
- **Simulator:** device type `Apple TV` (1080p) is the closest stand-in; it decodes with Mac hardware, so codec and performance claims are verified on the real device.

## Tech Stack
- Swift 6.2 (Xcode 26.3), SwiftUI, tvOS 18+ deployment target, built against the tvOS 26.2 SDK
- XcodeGen 2.46 (`project.yml`; generated `.xcodeproj` is not committed)
- Local Swift package `FooTubeCore` for all non-UI logic; Swift Testing for tests
- [alexeichhorn/YouTubeKit](https://github.com/alexeichhorn/YouTubeKit) (MIT): stream extraction, local only (`methods: [.local]`)
- Later phases: [b5i/YouTubeKit](https://github.com/b5i/YouTubeKit) vendored as `InnerTubeKit` (search/channels); [MPVKit](https://github.com/mpvkit/MPVKit) only if AVFoundation cannot combine separate audio and video streams; SponsorBlock REST API; `UserDefaults` for subscriptions (the persistent local store on tvOS)
- Dev tools: xcbeautify, swiftformat, xcode-build-server (sourcekit-lsp), yt-dlp (reference extractor for cross-checking)

## Commands
```
Generate project:   xcodegen generate
Core build:         swift build --package-path Packages/FooTubeCore
Core tests:         swift test --package-path Packages/FooTubeCore
Network tests:      FOOTUBE_NETWORK_TESTS=1 swift test --package-path Packages/FooTubeCore
Simulator build:    xcodebuild -project FooTube.xcodeproj -scheme FooTube -destination 'platform=tvOS Simulator,name=Apple TV' build | xcbeautify
Simulator run:      scripts/run-sim.sh   (build, install, launch on "Apple TV")
Screenshot:         xcrun simctl io booted screenshot <path>.png
Logs:               xcrun simctl spawn booted log stream --predicate 'subsystem == "com.felixrothballer.FooTube"'
Device run:         scripts/run-device.sh [launch args]   (build with -allowProvisioningUpdates, devicectl install + launch)
Format:             swiftformat .
LSP config:         xcode-build-server config -project FooTube.xcodeproj -scheme FooTube
Reference check:    yt-dlp --extractor-args "youtube:player_client=android_vr" -F <videoID>
```

## Project Structure
```
project.yml                  → XcodeGen definition (app target, signing, deployment target)
App/                         → SwiftUI views and tvOS-specific glue only (no networking, no parsing)
Packages/FooTubeCore/        → Logic: stream resolution, ID parsing, catalog, SponsorBlock, subscriptions
  Sources/FooTubeCore/
  Tests/FooTubeCoreTests/    → Unit tests (offline, fixtures) + opt-in network tests
  Tests/FooTubeCoreTests/Fixtures/ → Recorded JSON responses
Packages/InnerTubeKit/       → Vendored b5i/YouTubeKit, renamed (Phase 3 only)
tasks/                       → plan.md, todo.md, results.md (test runs on device)
SPEC.md, CONSTRAINTS.md, AGENTS.md
```

## Code Style
SwiftFormat defaults; Swift 6 strict concurrency; value types and `async/await`; no singletons; dependencies injected via initializers; errors are typed enums with a user-readable message.

```swift
public struct ResolvedStream: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case hls(playlist: String, variantCount: Int, maxHeight: Int)
        case muxed(itag: Int, height: Int)
    }

    public let videoID: VideoID
    public let url: URL
    public let kind: Kind
}

public protocol StreamResolver: Sendable {
    func resolve(_ videoID: VideoID) async throws(ResolveError) -> ResolvedStream
}

public enum ResolveError: Error, Hashable, Sendable {
    case noPlayableStream(detail: String)
    case unavailable(reason: String)
    case extractionFailed(reason: String)
}
```
Naming: types `UpperCamelCase`, no `Manager`/`Helper` suffixes; one primary type per file, file named after it. Logging via `os.Logger(subsystem: "com.felixrothballer.FooTube", category: …)`.

## Testing Strategy
- **Framework:** Swift Testing (`@Test`, `#expect`) in `FooTubeCoreTests`.
- **Unit (default, offline):** ID/URL parsing, stream selection rules (codec, resolution caps), SponsorBlock hashing and filtering, feed merge/sort, decoding from recorded fixtures. Run in `swift test` on every change.
- **Network (opt-in):** gated by `FOOTUBE_NETWORK_TESTS=1`; hit real YouTube/SponsorBlock with a fixed list of test IDs. Run at task end and when extraction is suspected broken. Never required for CI-style green.
- **UI:** `UITests/` (XCUITest) drives the Siri Remote with `XCUIRemote` for focus/navigation behaviour (Subscribe reachable, search reset, context menu, sidebar); needs network, run on demand, not part of `scripts/check.sh`. Visuals via Simulator screenshots; playback and performance by the human on the Apple TV, results in `tasks/results.md`.
- **Coverage:** no numeric target yet; set in `CONSTRAINTS.md`.

## Boundaries
- **Always:** keep logic in FooTubeCore and test it; run core tests and the Simulator build before calling a task done; select only formats the Apple TV HD can hardware-decode; log errors with source client and reason; update `AGENTS.md` when commands change.
- **Ask first:** adding any dependency (incl. MPVKit); enabling a remote fallback; any network request to a host other than YouTube or SponsorBlock; changing the bundle ID or deployment target; any Google-account login or cookie use.
- **Never:** commit secrets, cookies or tokens; hand-edit `FooTube.xcodeproj`; modify vendored `InnerTubeKit` without recording the change; skip or delete failing tests to get green; send watch data anywhere except the SponsorBlock hash-prefix lookup.

## Success Criteria
1. **Playback MVP:** on the Apple TV HD, ≥4 of 5 non-restricted test videos play with audio, start in < 3 s, seek and pause with the Siri Remote, show no ads, and still play 24 h later.
2. **Quality:** a video available in 1080p `avc1` plays at 1080p with A/V in sync after seeking, with no dropped-frame stutter visible to the user over 5 minutes.
3. **Discovery:** search returns results with thumbnails and paging; selecting a result or a channel upload plays it.
4. **SponsorBlock:** `sponsor` segments are skipped automatically with a brief notice; all other categories (`selfpromo`, `interaction`, `intro`, `outro`, `preview`, `music_offtopic`, `filler`) show a skip button; a failed SponsorBlock request never delays playback.
5. **Subscriptions:** a Subscribe/Unsubscribe button on the channel page adds/removes a channel; subscriptions persist across relaunch; the feed lists recent uploads across subscriptions, newest first, shown from cache instantly and then refreshed.

## Decisions Recorded
- No remote extraction fallback initially; self-hosted YouTubeKit-Server may be added later (ask first).
- SponsorBlock: auto-skip `sponsor`; all other categories show a skip button.
- Subscriptions start empty; added only via the channel page. No Takeout import.
- Device runs tvOS 26 (owner reports "25 or 26"; Apple went from 18 to 26, so ≥ 18 either way). Deployment target tvOS 18 stands.

## Out of Scope (possible later)
- **Subscription sync/backup.** iCloud/CloudKit sync needs the iCloud entitlement, which a free Personal Team cannot sign; it would require the paid Apple Developer Program. Alternatives without it: export/import a JSON file, or sync via a self-hosted server alongside a future YouTubeKit-Server.
- Google Takeout `subscriptions.csv` import.
- Remote extraction fallback (self-hosted YouTubeKit-Server).

## Open Questions
- None blocking.
