# FooTube — agent guide

Private, sideloaded tvOS YouTube client for an Apple TV HD (H.264 only, 1080p, tvOS 26). No ads because streams are resolved on-device and played natively.

Read CONSTRAINTS.md before writing code. Do not weaken it to make a change pass.

- What we build: `SPEC.md` · How/order: `tasks/plan.md` · Tasks: `tasks/todo.md` · Device/test results: `tasks/results.md`
- Background research: `tvos-youtube-client-findings.md`

## Commands
| Purpose | Command |
|---|---|
| Fast checks (after edits) | `scripts/check.sh fast` |
| All checks (task end, must exit 0) | `scripts/check.sh task` |
| Generate Xcode project | `xcodegen generate` (never hand-edit `FooTube.xcodeproj`; it is gitignored) |
| Core build / tests | `swift build --package-path Packages/FooTubeCore` / `swift test --package-path Packages/FooTubeCore` |
| Network tests (real YouTube) | `FOOTUBE_NETWORK_TESTS=1 swift test --package-path Packages/FooTubeCore` |
| Run and auto-play a video | `scripts/run-sim.sh -play <id or URL>` (launch argument read by `PlayByIDView`; also works with `devicectl … process launch`) |
| Build + run in Simulator | `scripts/run-sim.sh` |
| Screenshot | `xcrun simctl io "Apple TV" screenshot <path>.png` |
| Logs | `xcrun simctl spawn "Apple TV" log stream --predicate 'subsystem == "com.felixrothballer.FooTube"'` |
| Format | `swiftformat .` |
| LSP setup (after first `xcodegen generate`) | `xcode-build-server config -project FooTube.xcodeproj -scheme FooTube` |
| Reference extractor | `yt-dlp --extractor-args "youtube:player_client=android_vr" -F <videoID>` |

Simulator: `Apple TV` (1080p, closest to Apple TV HD). It decodes with Mac hardware: codec and performance claims need the real device.

## Layout
- `App/` — SwiftUI views and tvOS glue only. No networking or parsing here.
- `Packages/FooTubeCore/` — all logic (stream resolution, ID parsing, catalog, SponsorBlock, subscriptions) with Swift Testing tests in `Tests/FooTubeCoreTests/` (fixtures in `Fixtures/`).
- `project.yml` — XcodeGen definition. Bundle `com.felixrothballer.FooTube`, team `X94768F5PD` (free Personal Team), tvOS 18+.
- `scripts/` — `check.sh` (CONSTRAINTS.md checks), `floor-guard.mjs`, `run-sim.sh`.

## Conventions
- Swift 6 language mode; warnings are errors in our targets (app and FooTubeCore).
- Formats for Apple TV HD: video `avc1` ≤ 1080p, audio AAC. Never select VP9/AV1/Opus-only.
- Logging: `os.Logger(subsystem: AppInfo.logSubsystem, category: …)`.
- Network tests are opt-in via `FOOTUBE_NETWORK_TESTS=1`; offline tests use recorded fixtures.
- New dependencies, remote fallbacks, other hosts, Google login: ask first (SPEC → Boundaries).
- One commit per task; message names the task (e.g. `T2: …`).
