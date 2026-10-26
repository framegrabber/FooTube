# Spec: ios-app

Module `ios-app` of FooTube's self-hosted sync (capability map: `SYNC.md`). Depends on `sync-client`. Written overnight on 2026-10-26 without the owner's review; it is a spec and plan only, implementation waits for review (see **Open Questions**).

## Objective
FooTube on iPhone and iPad: the same ad-free playback, search, channels, subscriptions feed, Watch Later and History as on the Apple TV, sharing state through the household's sync Worker. Continue on the phone where the TV stopped, and the other way round.

**Users:** the builder's household, on iPhones/iPads sideloaded with the same free Personal Team (7-day expiry, at most 3 sideloaded apps per device).

**Stories:**
1. As a viewer on an iPhone, I open FooTube, see my subscriptions feed and continue a video at the position where I stopped on the TV.
2. As a viewer on an iPad, I search, open a channel, subscribe, and the channel shows up on the TV.
3. As a viewer, I watch in Picture in Picture and AirPlay to another screen.
4. As a viewer, I share a YouTube link from Safari or the YouTube app to FooTube and it plays (or is saved to Watch Later).

## Approach
- **One multiplatform app target** in `project.yml` (`supportedDestinations: [tvOS, iOS]`, iPhone and iPad), deployment target iOS 18, same bundle ID. FooTubeCore already builds for any platform; add `.iOS(.v18)` to `Package.swift`.
- **Shared code:** models (`*Model.swift`), `PlaybackController`/`PlayerSession` (AVKit on both), `RemoteImage`, `LocalizedText`, `SyncModel`. **Per platform:** root navigation and screens. tvOS keeps its views; iOS gets `TabView` (iPhone) / sidebar-adaptable `TabView` (iPad) with NavigationStacks, grids sized for touch, swipe actions and context menus instead of focus.
- **Playback:** same filtered-HLS pipeline and format policy (`avc1` ≤ 1080p, AAC). Every iPhone/iPad supported by iOS 18 decodes H.264 in hardware; higher resolutions or HEVC are out of scope. `AVPlayerViewController` with PiP (`AVAudioSession` `.playback`, background-audio mode for PiP only) and AirPlay; SponsorBlock skipping, chapters and Up next as on tvOS where AVKit on iOS supports them (iOS has no `AVContentProposal`: Up next becomes an overlay with the same 10 s countdown).
- **Sync configuration:** same launch arguments, passed by a new `scripts/run-ios-device.sh` (devicectl), plus a Settings screen on iOS where the URL and token can be pasted (iOS has a keyboard and clipboard; the token is stored in the Keychain).
- **Sharing:** the app registers no URL scheme for YouTube; a Share Extension is a separate target and app ID, which the free team's App ID limit makes costly, so story 4 is done through an `onOpenURL` handler for a `footube://` scheme plus a Shortcut the builder installs ("Open in FooTube"), documented in the README.

## Commands
```
Generate:      xcodegen generate
iOS Simulator: xcodebuild -project FooTube.xcodeproj -scheme FooTube -destination 'platform=iOS Simulator,name=iPhone 17' build
Run:           scripts/run-sim.sh --ios     (boots "iPhone 17")
Device:        scripts/run-ios-device.sh [launch args]
```

## Testing Strategy
Core logic is shared and already tested. iOS UI: build both platforms in `scripts/check.sh task`; Simulator screenshots of each tab on iPhone and iPad; one UI test per platform for the basic play path. Sync between an iPhone Simulator and the `Apple TV` Simulator against `wrangler dev`.

## Boundaries
- **Always:** keep tvOS behaviour unchanged (all existing UI tests pass); share models, split views.
- **Ask first:** new targets (extensions), background modes beyond PiP audio, any change to the format policy.
- **Never:** fork FooTubeCore per platform.

## Success Criteria
1. The app builds for tvOS and iOS with zero warnings; `scripts/check.sh task` covers both.
2. On an iPhone Simulator: feed, search, channel, play with resume, Watch Later, History, Settings work; PiP starts from the player.
3. A position recorded on the iPhone Simulator resumes on the `Apple TV` Simulator after sync, and back.
4. tvOS UI tests still pass.

## Open Questions (block implementation)
- Was the iOS app meant mainly for watching, or for managing what plays on the TV? This spec assumes watching (full app).
- Is spending one of the 3 sideloaded-app slots on each iPhone/iPad acceptable? (Two if a Share Extension is wanted later.)
- Keep Up next and chapters on iOS, or drop them for a simpler first version?
