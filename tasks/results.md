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
