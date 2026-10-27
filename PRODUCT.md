# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

Apple-native, on two platforms from one SwiftUI app target: **tvOS** first (deployment target tvOS 18, built against the tvOS 26 SDK; 10-foot UI, focus engine, Siri Remote) and **iPhone/iPad** (iOS 18; touch, tab bar on iPhone that becomes a sidebar on iPad, context menus, swipe actions, pull to refresh, Dynamic Type). Models, sync and playback are shared; each platform has its own screens following its own conventions.

## Users

Anyone who builds and sideloads FooTube onto their own Apple TV, iPhone or iPad: technically capable owners comfortable with Xcode, a Mac and an Apple ID, plus the people in their household who then just use it from the couch with the Siri Remote or on their phone. Design decisions serve unknown households, setups and system languages, not only the original author's. The original reference device is an Apple TV HD on a 1080p TV.

## Product Purpose

Watch YouTube on Apple TV, iPhone and iPad without ads, without a Google account and without tracking. Streams are resolved on the device and played in Apple's native player; subscriptions, history and Watch Later stay on the device, optionally synced between the household's devices through a server the builder runs. On iPhone and iPad FooTube also collects: videos shared to an "Add to FooTube" Shortcut (or a Safari bookmark) land in Watch Later on every device. Success: videos start quickly, play smoothly at up to 1080p H.264 on an Apple TV HD, and finding and following channels works without any account.

## Positioning

No web player, no third-party server, no account: extraction happens on-device and playback is `AVPlayerViewController`, so there are no ad requests and no watch data leaves the household (except the SponsorBlock hash-prefix lookup); the only server is the optional sync Worker the builder deploys. Built for the oldest supported hardware (Apple TV HD, A8, H.264 only), so it runs on every Apple TV with tvOS 18+. Self-built and sideloaded; not on the App Store.

## Operating Context

- Apple TV: living-room TV, viewed from the couch, operated only with the Siri Remote (1st gen touch surface: swipe, click, Menu, Play/Pause); long press opens a video's context menu. Menu goes back one level, then to the tab bar, then exits (tvOS convention).
- iPhone/iPad: touch, in portrait and landscape; touch and hold opens the same video menu, swipe actions in Watch Later and History, pull to refresh. The player is full screen with Picture in Picture and AirPlay; no Up next (iOS has no system version).
- Tabs: Subscriptions, Search, Watch Later, History, Settings.
- Appearance follows the device's Light/Dark setting; titles and dates follow the system language.
- Setup ritual for builders: clone, `xcodegen`, local signing config, pair the Apple TV (or connect the iPhone/iPad with Developer Mode on) in Xcode, `scripts/run-device.sh` (or `scripts/run-ios-device.sh`). With a free Apple ID the install expires after 7 days and must be rebuilt; data survives.

## Capabilities and Constraints

- Features: account-free subscriptions feed with channel filter (tvOS sidebar, iOS avatar row); search with live suggestions and matching channels; channel pages with Subscribe; native player with scrubbing, info panel, original audio track, subtitles off by default; SponsorBlock (auto-skip `sponsor`, Skip button for other categories); chapters from the description (tvOS chapter row, iOS chapter list); Up next after a 10-second countdown (tvOS only); Picture in Picture and AirPlay (iOS); resume, History, Watch Later; adding to Watch Later from a Shortcut, a bookmark or a `footube://` link.
- Hardware: video `avc1` ≤ 1080p and AAC audio only; A8 CPU, 2 GB RAM, so the UI stays light and thumbnail grids must scroll smoothly.
- State lives in `UserDefaults` on the device, optionally synced to the builder's own Cloudflare Worker (iCloud would need the paid developer program); no Takeout import.
- Network hosts: YouTube, SponsorBlock and, when configured, the builder's sync Worker only. Remote fallbacks, other hosts, new dependencies and Google login are ask-first (SPEC → Boundaries).
- Known limits: made-for-kids videos don't play; relative upload dates are parsed only in English and German; YouTube API changes can break playback or search until upstream libraries catch up.
- Not affiliated with YouTube or Google; use is against YouTube's Terms of Service, stated plainly in the README.

## Brand Commitments

- Name: FooTube.
- Binding: follows Apple's design for each platform. tvOS: system components, focus engine, native lockups with lift and tilt. iPhone/iPad: system tab bar and sidebar, navigation stacks with large titles, lists and forms, context menus. Both: system typography, Light and Dark appearance. No custom visual world; brand shows only in small details.
- Existing assets: app icon and Top Shelf images in `App/Assets.xcassets/App Icon & Top Shelf Image.brandassets`, the iPhone/iPad icon in `App/Assets.xcassets/AppIcon.appiconset` (both generated by `scripts/make-icon.swift`).
- Voice (README): plain, direct, honest about limits and legal caveats.

## Evidence on Hand

- Screenshots: `docs/screenshots/` (subscriptions, search, channel, chapters, upnext).
- Device test results: `tasks/results.md`. Background research: `docs/research.md`.
- Credits: b5i/YouTubeKit (vendored as InnerTubeKit), alexeichhorn/YouTubeKit, SponsorBlock (CC BY-NC-SA 4.0). MIT license.
- No user counts, testimonials, press or performance benchmarks beyond `tasks/results.md`; do not invent any.

## Product Principles

1. Native over novel: if tvOS has a component or convention for it, use that; the remote and focus behave exactly as in Apple's apps.
2. Nothing leaves the household: no account, no third-party server, no telemetry; the only server is the one the builder runs. New hosts or logins are not a design option.
3. Design for the weakest box: everything must feel smooth on an Apple TV HD at 1080p.
4. The video is the product: the UI gets out of the way of finding and watching.
5. Honest about limits: caveats, breakage risk and unsupported content are stated, not hidden.
