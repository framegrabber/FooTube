# Spec: ios-app

Module `ios-app` of FooTube's self-hosted sync (capability map: `SYNC.md`). Depends on `sync-client`; uses the inbox from `browser-inbox`. First written overnight on 2026-10-26; open questions answered by the owner on 2026-10-27 (see **Decisions**).

## Objective
FooTube on iPhone and iPad, for two jobs: **watching** (the same ad-free playback, search, channels, subscriptions feed, Watch Later, History, SponsorBlock and chapters as on the Apple TV; no Up next, see Decisions) and **collecting** (saving a video to Watch Later from wherever it turns up, so it's waiting on every TV). State is shared through the household's sync Worker: continue on the phone where the TV stopped, and the other way round.

**Users:** the builder's household, on iPhones/iPads sideloaded with the same free Personal Team (7-day expiry, at most 3 sideloaded apps per device; FooTube takes one).

**Stories:**
1. As a viewer on an iPhone, I open FooTube, see my subscriptions feed and continue a video at the position where I stopped on the TV.
2. As a viewer on an iPad, I search, open a channel, subscribe, and the channel shows up on the TV.
3. As a viewer, I watch in Picture in Picture and AirPlay to another screen; sponsors are skipped and chapters are listed.
4. As a viewer in the YouTube app or Safari on my iPhone, I share a video to "Add to FooTube" and it's in Watch Later on every device after their next sync.
5. As a viewer with FooTube open, I long-press a video and choose Add to Watch Later, as on the TV.

## Approach
- **One multiplatform app target** in `project.yml` (tvOS + iOS, iPhone and iPad), deployment target iOS 18, same bundle ID. `Package.swift` adds `.iOS(.v18)`; FooTubeCore has no tvOS-only code.
- **Shared code:** models (`*Model.swift`), `SyncModel`, `PlaybackController`/`PlayerSession`, `RemoteImage`, `LocalizedText`, `ErrorMessage`. **Per platform:** root navigation and screens. tvOS keeps its views unchanged; iOS gets a `TabView` (sidebar-adaptable on iPad) with NavigationStacks, touch-sized grids, context menus and swipe actions. Platform files live in `App/tvOS/` and `App/iOS/` only where views differ.
- **Playback:** same filtered-HLS pipeline and format policy (`avc1` ≤ 1080p, AAC; every iOS 18 device decodes H.264 in hardware). `AVPlayerViewController` full screen with PiP (`AVAudioSession` `.playback`, background-audio mode only for PiP) and AirPlay. SponsorBlock skipping as on tvOS. **Chapters:** as `navigationMarkerGroups` if AVKit on iOS shows them, otherwise a chapter list in a sheet that seeks; checked in the first player task. **No Up next on iOS:** iOS has no system Up next (`AVContentProposal` is tvOS-only), and the owner chose to skip it rather than build an overlay; the player simply ends.
- **Sync configuration:** the existing file drop (`scripts/sync-env.sh`) works for devices installed from the Mac (`devicectl device copy to`). iOS Settings additionally lets the user paste URL and token (keyboard and clipboard exist on iOS); stored the same way (UserDefaults + Keychain).
- **Adding from anywhere (story 4)** without a second app slot:
  - **Shortcut "Add to FooTube"** in the share sheet: takes the shared URL, extracts the video ID, and posts it to `POST /v1/inbox` with the **inbox token** (add-only). Works even when FooTube isn't open or installed on that device; every FooTube picks it up on its next Watch Later sync. README gives step-by-step build instructions (Shortcuts can't be generated from the repo).
  - **Safari bookmarklet:** the existing `.bookmarklet.txt` works in Safari on iPhone/iPad too; documented.
  - **`footube://` URL scheme** in the app: `footube://play?v=<id>` and `footube://watch-later?v=<id>[&title=<title>]`, for Shortcuts that should open FooTube instead. The title is cleaned like an inbox title (SPEC-browser-inbox → Client).

## Commands
```
Prerequisite:  xcodebuild -downloadPlatform iOS        (iOS Simulator runtime, not installed on this Mac yet)
Generate:      xcodegen generate
iOS build:     xcodebuild -project FooTube.xcodeproj -scheme FooTube -destination 'platform=iOS Simulator,name=iPhone 17' build
Run (sim):     scripts/run-sim.sh --ios [launch args]   (boots "iPhone 17"; --ipad for an iPad)
Run (device):  scripts/run-ios-device.sh [launch args]  (first paired iPhone/iPad; FOOTUBE_DEVICE to choose)
```

## Testing Strategy
Core logic is shared and already tested; new Core code (URL scheme parsing, ID extraction for the Shortcut docs if any) gets unit tests. `scripts/check.sh task` builds both platforms with warnings as errors. iOS UI: Simulator screenshots of each tab on iPhone and iPad; one XCUITest per platform for the basic play path (search → play → back). Sync between an iPhone Simulator and the `Apple TV` Simulator against `wrangler dev`: subscription, Watch Later, resume position. Shortcut: manual on a real iPhone by the owner.

## Boundaries
- **Always:** keep tvOS behaviour unchanged (all existing UI tests pass); share models, split views; new strings in `Localizable.xcstrings` with German.
- **Ask first:** new targets (extensions, widgets), background modes beyond PiP audio, any change to the format policy, a different inbox token scope.
- **Never:** fork FooTubeCore per platform; put the household sync token into a Shortcut (only the add-only inbox token).

## Success Criteria
1. The app builds for tvOS and iOS with zero warnings; `scripts/check.sh task` covers both.
2. On iPhone and iPad Simulators: feed, search with suggestions, channel with Subscribe, play with resume, chapters, Watch Later (long press add/remove), History, Settings with sync status; PiP starts from the player.
3. A position recorded on the iPhone Simulator resumes on the `Apple TV` Simulator after sync, and back.
4. A `POST /v1/inbox` as the Shortcut sends it (scripted with curl against `wrangler dev`) shows up in Watch Later on the iPhone Simulator after Refresh; `footube://watch-later?v=…` adds a video.
5. tvOS UI tests still pass.

## Decisions
- **Both jobs** (watching and collecting), owner 2026-10-27.
- **One app slot per iPhone/iPad is fine**, owner 2026-10-27. A Share Extension is not built: an app extension has its own App ID and, as far as I know from sideloading tools' docs, counts as another app against the 3-app limit [unverified]; the Shortcut covers the share sheet without it. Revisit if the Shortcut is too clunky.
- **Chapters stay on iOS; Up next is dropped there** because iOS has no native version, owner 2026-10-27.
- **iOS Simulator runtime download approved**, owner 2026-10-27.

## Open Questions
- None.
