# FooTube — agent guide

Sideloaded tvOS YouTube client for an Apple TV HD (H.264 only, 1080p, tvOS 26). No ads because streams are resolved on-device and played natively. User-facing overview and setup: `README.md`.

Read CONSTRAINTS.md before writing code. Do not weaken it to make a change pass.

- What we build: `SPEC.md` · How/order: `tasks/plan.md` · Tasks: `tasks/todo.md` · Device/test results: `tasks/results.md`
- Background research: `docs/research.md`

## Commands
| Purpose | Command |
|---|---|
| Fast checks (after edits) | `scripts/check.sh fast` |
| All checks (task end, must exit 0) | `scripts/check.sh task` |
| Generate Xcode project | `xcodegen generate` (never hand-edit `FooTube.xcodeproj`; it is gitignored) |
| Core build / tests | `swift build --package-path Packages/FooTubeCore` / `swift test --package-path Packages/FooTubeCore` |
| Network tests (real YouTube) | `FOOTUBE_NETWORK_TESTS=1 swift test --package-path Packages/FooTubeCore` |
| Sync network tests (`wrangler dev` on localhost only, they write its stores; own variables so a shell set up for `run-sim.sh` never runs them) | `FOOTUBE_SYNC_TEST_URL=http://localhost:8787 FOOTUBE_SYNC_TEST_TOKEN=<token from ../FooTubeSyncBackend/.dev.vars> swift test --package-path Packages/FooTubeCore --filter SyncNetworkTests` |
| Re-record sync fixtures (fresh `wrangler dev --persist-to <empty dir>`, migrations applied) | `FOOTUBE_SYNC_TEST_URL=… FOOTUBE_SYNC_TEST_TOKEN=… [FOOTUBE_SYNC_UNCONFIGURED_URL=…] node scripts/record-sync-fixtures.mjs` |
| Debug launch arguments | `scripts/run-sim.sh -play <id or URL>` (`RootView`), `-subscribe <id,id>` (`RootView`), `-search <query>`, `-channel <channelID>` (`SearchView`, Search tab); once per launch; also work with `devicectl … process launch` |
| Build + run in Simulator | `scripts/run-sim.sh` |
| Build + run on the Apple TV | `scripts/run-device.sh [launch args]` (first paired Apple TV; `FOOTUBE_DEVICE=<name or id>` to choose; needs `Config/Signing.local.xcconfig`; free team → rebuild every 7 days) |
| Run with sync | `FOOTUBE_SYNC_URL=<Worker URL> FOOTUBE_SYNC_TOKEN=<token> scripts/run-sim.sh` (or `run-device.sh`), or put both variables in `~/.config/footube/sync.env` (`FOOTUBE_SYNC_ENV=<file>` for another); the scripts copy a temporary `{"url","token"}` file into the installed app's container (`Library/Caches/footube-sync.json`, `scripts/sync-env.sh`, token never printed or passed as a launch argument), the app saves URL in `UserDefaults` and token in the Keychain and deletes the file; `-syncReset YES` turns sync off. URL: `https`, or `http://localhost`/`127.0.0.1` for `wrangler dev`; token ≥ 64 characters |
| UI tests (remote-driven focus checks, network) | `xcodebuild test -project FooTube.xcodeproj -scheme FooTube -destination 'platform=tvOS Simulator,name=Apple TV' -resultBundlePath /tmp/ui.xcresult` (screenshots: `xcrun xcresulttool export attachments --path /tmp/ui.xcresult --output-path <dir>`) |
| Screenshot | `xcrun simctl io "Apple TV" screenshot <path>.png` |
| Logs | `xcrun simctl spawn "Apple TV" log stream --predicate 'subsystem ENDSWITH ".FooTube"'` |
| Format | `swiftformat .` |
| LSP setup (after first `xcodegen generate`) | `xcode-build-server config -project FooTube.xcodeproj -scheme FooTube` |
| Reference extractor | `yt-dlp --extractor-args "youtube:player_client=android_vr" -F <videoID>` |

Simulator: `Apple TV` (1080p, closest to Apple TV HD). It decodes with Mac hardware: codec and performance claims need the real device.

## Layout
- `App/` — SwiftUI views and tvOS glue only. No networking or parsing here.
- `Packages/FooTubeCore/` — all logic (stream resolution, ID parsing, catalog, SponsorBlock, subscriptions) with Swift Testing tests in `Tests/FooTubeCoreTests/` (fixtures in `Fixtures/`).
- `project.yml` — XcodeGen definition, tvOS 18+. Team and bundle ID prefix come from `Config/Signing.xcconfig`, which includes the developer's gitignored `Config/Signing.local.xcconfig` (template: `Signing.local.xcconfig.example`).
- `scripts/` — `check.sh` (CONSTRAINTS.md checks), `floor-guard.mjs`, `run-sim.sh`, `run-device.sh` (both source `sync-env.sh`), `make-icon.swift`, `record-sync-fixtures.mjs`.
- `docs/` — research notes and README screenshots.

## Conventions
- Swift 6 language mode; warnings are errors in our targets (app and FooTubeCore).
- Formats for Apple TV HD: video `avc1` ≤ 1080p, audio AAC. Never select VP9/AV1/Opus-only.
- Logging: `os.Logger(subsystem: AppInfo.logSubsystem, category: …)`.
- User-facing text: `App/Localizable.xcstrings` (English source, German). Add every new string with a German translation; build with `SWIFT_EMIT_LOC_STRINGS=YES` and read the `.stringsdata` files to get exact keys. Core's English `message`/names are for logs; the app shows `userMessage`/`localizedName` (`App/LocalizedText.swift`).
- Network tests are opt-in via `FOOTUBE_NETWORK_TESTS=1`; offline tests use recorded fixtures.
- New dependencies, remote fallbacks, other hosts, Google login: ask first (SPEC → Boundaries).
- One commit per task; message names the task (e.g. `T2: …`).
