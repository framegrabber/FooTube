# Test results

## 2026-10-19 — T2 extraction spike (Mac, home IP, YouTubeKit 0.4.9)

Command: `FOOTUBE_NETWORK_TESTS=1 swift test --package-path Packages/FooTubeCore --filter ResolverNetworkTests`

| Case | ID | FooTube resolver | First media bytes | yt-dlp cross-check |
|---|---|---|---|---|
| normal (Big Buck Bunny) | `aqz-KE-bpKQ` | HLS, 7 H.264 variants up to 1080p60 | 200 | ok |
| label music video | `dQw4w9WgXcQ` | HLS, 7 H.264 variants up to 1080p | 200 | ok |
| made for kids | `XqZsoesa55w` | **fails**: YouTubeKit returns 0 streams and no HLS | — | `android_vr` and `visionos` clients return H.264 up to 360p + muxed itag 18 |
| long (> 2 h) | `PkcnAB09ZXU` | HLS, 7 H.264 variants up to 1080p | 200 | — |
| livestream | `rFZHOHl-L8A` | HLS, 7 H.264 variants up to 1080p | 200 | — |
| age-restricted (expected to fail) | `HtVdAasjOgU` | fails: muxed itag 18 → HTTP 403 | — | — |

**Result: 4/5 → Checkpoint A passes.**

### Findings
- **YouTube's visionOS client returns an HLS master for VOD, not only live.** It mixes H.264 (`avc1`, up to 1080p, AAC audio renditions) and VP9 (up to 4K) variants. Filtered to H.264 ≤ 1080p / level ≤ 4.2 it is exactly what the Apple TV HD can decode, with adaptive bitrate and audio included. This is likely the 1080p answer for Phase 2 without MPVKit or stream merging (to be confirmed in AVPlayer on device).
- YouTubeKit's progressive (muxed) streams come from the `WEB` client and return **HTTP 403** (PO token required for GVS). Its adaptive H.264 streams come from `VISIONOS` and return 206. So the muxed fallback is mostly dead; the resolver checks for 403 before returning one.
- YouTubeKit does not expose which client produced a stream or the itag number publicly; the itag is read from the URL query.
- Made-for-kids: YouTubeKit gets nothing while yt-dlp's `visionos` client does → likely a YouTubeKit request difference. Not blocking; revisit if kids content matters.

## 2026-10-19 — T3/T4 in the `Apple TV` Simulator (tvOS 26.2, Mac decoders)

Launched with `scripts/run-sim.sh -play <id>`; values from the debug diagnostics overlay and `playback` log.

| Video | Result | First frame (incl. resolve) | Variant after ~5 s |
|---|---|---|---|
| Big Buck Bunny `aqz-KE-bpKQ` | plays, no ads | 1.98 s (resolve 1.43 s) | 1080p, 7.4 Mbps, 0 dropped |
| Rick Astley `dQw4w9WgXcQ` (also as `youtu.be/…?si=` URL) | plays, no ads, captions button offered | 2.25 s | 1080p, 4.7 Mbps, 0 dropped |
| Made for kids `XqZsoesa55w` | clear error on screen (no stream) | — | — |

- The filtered master now lists the best ≤ 720p variant first (AVPlayer starts with the first variant); before, playback began at 240p.
- Not yet verified: Siri Remote seek/pause and Menu-to-exit (no remote input available in the Simulator from the command line), and anything on the Apple TV HD.

## 2026-10-19 — T12–T15 in the `Apple TV` Simulator

| Feature | Check | Result |
|---|---|---|
| SponsorBlock auto-skip | `zergV5YUDjk` (sponsor 51.2–102.2 s) | log `skipping sponsor 51.179-102.219` at ~51.7 s; "Skipped sponsor" notice shown |
| SponsorBlock skip button | `e2_q_fE2uQY` (intro 0–14.4 s) | "Skip Intro" button appears bottom-right once the transport bar hides (AVPlayerViewController `contextualActions`) |
| Search | `-search "blender open movie"` | 4-column grid with thumbnails, durations, channel/views/age; page 2 via continuation (network test) |
| Channel page | `-channel UCSMOQeBJ2RAnuFungnQOxLg` | avatar, name, "1.25M subscribers", uploads grid; page 2 via continuation (network test) |
| Subscriptions | `-subscribe <Blender>,<Rick Astley>`, then relaunch without it | both channels still listed (SwiftData persisted) |
| Feed | Subscriptions tab with 2 channels | "Latest — Updated now", 60 videos newest first ("5 days ago", "2 weeks ago", …) |

Not verifiable without a remote (Simulator has no CLI remote input): focus movement, pressing Skip Intro, Subscribe/Unsubscribe button, long-press context menu "Open channel", Menu to exit the player, seeking.

Known gaps: made-for-kids videos fail (YouTubeKit returns no streams); some videos fail extraction (`p4aN7HXGlRk`, `V42hzL11Kpk`: `extractError` from YouTubeKit).

## 2026-10-22 — H1 scrubbing-thumbnail spike in the `Apple TV` Simulator

| Check | Method | Result |
|---|---|---|
| TS segments start with an IDR | First, middle and last segment of the 144p and 240p variants of `aqz-KE-bpKQ`, `zergV5YUDjk`, `5p7b-GCufX4` (18 segments), parsed for the first video NAL units | All 18: AUD, SPS, PPS, (SEI), IDR; every segment decodes on its own |
| AVKit uses whole-segment I-frame entries | Throwaway: two `#EXT-X-I-FRAME-STREAM-INF` lines in the master, I-frame playlist rewritten from the media playlist on request; UI test pauses, steps and holds right on `aqz-KE-bpKQ` | Thumbnails above the scrubber at 00:31, 00:41, 00:58, 01:03 and while scanning (01:25) |
| When AVKit asks | `NSLog` in the resource loader | ~0.8 s after the master loads, during start-up (not on first scrub); it chose 240p over 144p |
| Start time | `first frame after` log, 5 launches each | After resolve: median 0.68 s with and without; totals 2.55 vs 2.42 s, difference within resolve (network) noise |

Decision: go. Not yet known: start time and scrubbing smoothness on the Apple TV HD.

## 2026-10-22 — H2–H3 scrubbing thumbnails in the `Apple TV` Simulator

| Check | Method | Result |
|---|---|---|
| Lazy serving (first H3 design) failure mode | I-frame sources pointed at an unreachable host; then an empty I-frame playlist as fallback | Both fail the whole video: black screen, CoreMedia -12642 "no media files in stream playlist", main item stopped. Lazy design dropped; owner chose build-first |
| Thumbnails (build-first) | Throwaway UI test on `aqz-KE-bpKQ`: pause, step right twice, hold right | Thumbnails at 01:17, 01:27 and while scanning (01:43); log: "2 I-frame playlists", AVKit requests both ~0.76 s after load, served from memory |
| Live stream | `-play rFZHOHl-L8A` | Plays normally, "0 I-frame playlists" |
| Start time | `first frame after`, 5 launches of `aqz-KE-bpKQ` each, medians | Before 2.42 s (resolve 1.76); build-first 2.84 s (resolve 2.12, +0.36 s, within the run-to-run resolve spread of up to 0.8 s). Device measurement pending |
| Real YouTube | `FOOTUBE_NETWORK_TESTS=1`, `ResolverNetworkTests` | Big Buck Bunny, music video, > 2 h video: 2 I-frame playlists each; livestream: 0; made-for-kids still fails (known) |
