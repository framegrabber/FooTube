# Scrubbing thumbnails

## Problem Statement
How might we let someone on the couch find a known moment in a video by sight, inside Apple's native scrubber, without slowing playback start on an Apple TV HD?

## Recommended Direction
Give AVKit the I-frame playlists YouTube doesn't ship. FooTube's filtered HLS master gains one `#EXT-X-I-FRAME-STREAM-INF` line for each of the 144p and 240p H.264 variants, pointing at `footube-hls://iframe/<id>/<height>.m3u8`. When AVKit requests one, `PlaylistLoader` fetches that variant's googlevideo media playlist and rewrites it as an `EXT-X-I-FRAMES-ONLY` playlist: same durations, same segment URLs, one entry per segment, no byte ranges. Start-up cost is two lines in the master; the rewrite runs lazily, off the start path.

Declaring both variants with their real `BANDWIDTH` lets AVKit choose the sharper one when the connection allows, using the logic it already has for video. The same playlists drive tvOS scanning (fast-forward and rewind with pictures), so one change gives two ways to find a scene.

Density is capped at one image per segment (~4 s). That's also the ceiling of YouTube's storyboards (5 s), so no other route on the table is denser.

## Key Assumptions to Validate
- [ ] AVKit shows thumbnails from whole-TS-segment I-frame entries. Test: Simulator scrub, then the Apple TV HD.
- [ ] Start time unchanged. Test: compare the "first frame after" log lines with and without the I-frame lines on the device, and log when AVKit first requests an I-frame playlist (at load or at first scrub).
- [ ] Segments start with an IDR. Test: parse the first video packet of a few 144p segments (a NAL type 5 must come first).
- [ ] Thumbnails arrive fast enough. Test: scrub a 30+ minute video on the device; if it lags, variant 4 (warming) is next.
- [ ] AVKit picks between 144p and 240p. Test: log which I-frame playlist the loader serves.

## MVP Scope
In: the I-frame lines in `HLSMasterPlaylist.filtered`, the I-frame media-playlist rewrite in Core with fixture-based tests, lazy serving in `PlaylistLoader`, logging of I-frame requests, a Simulator check and a device check.
Out: everything in "Not Doing".

## Not Doing (and Why)
- Keyframe-only byte ranges (variant 3): needs every segment's start read before the playlist exists; only worth it if whole segments prove too heavy.
- Background warming (variant 4): AVKit's network stack bypasses our cache, so warming means serving segments ourselves. Only if the device shows lag.
- Storyboards encoded on the device (variant 7): large pipeline, only ~3 of 4 videos have storyboards, no denser than this. Fallback only if AVKit rejects segment I-frames.
- A custom overlay or other surfaces (variant 6): ruled out; the scrubber is the only place.
- VP9 or higher variants: the Apple TV HD can't decode VP9, and higher H.264 variants cost more traffic per thumbnail.

## Open Questions
- Does AVKit request I-frame playlists at asset load or only on the first scrub? This decides whether "no slower start" holds automatically.
- Is a 4 s spacing fine enough to "land on the scene"? Only the device test answers that.

## Research Notes (2026-10-22)
- Apple's HLS authoring spec: I-frame playlists "MUST be provided to support scrubbing and scanning UI". https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices
- Prior art: https://github.com/HarshLabs/jellyfin-plugin-native-trickplay (adds `#EXT-X-I-FRAME-STREAM-INF` for AVKit; warns about tvOS 26 error -12642 when a declared I-frame playlist is unavailable).
- Live YouTube HLS (via FooTube's resolver; yt-dlp was blocked by the SABR experiment): 17 variants (7 H.264, 10 VP9), no I-frame playlists; VOD media playlists, HLS version 3, MPEG-TS segments of ~3–5 s, no byte ranges.
- Cost for a 10:34 video (123 segments): 144p ≈ 20 KB per segment, ≈ 2.4 MB total; 240p ≈ 70 KB per segment, ≈ 8.5 MB total.
- Storyboards (player endpoint, `VideoInfosResponse.storyboard`): 320×180 (3×3 sheets) or 160×90 (5×5), one frame every 5 s; 3 of 4 test videos had one.
- `AVAssetWriterDelegate` segment output: tvOS 14+ (needed only for the storyboard fallback).
