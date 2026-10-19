# Private ad-free YouTube client for tvOS: findings so far

## Goal
Build a private (non-distributed) tvOS app that plays YouTube without ads, similar to how the Helium browser achieves it via a built-in uBlock Origin.

## Why the browser approach doesn't transfer
- Helium blocks ads by filtering page elements and manipulating player data inside the web player.
- tvOS has no public WebKit/`WKWebView`, so loading youtube.com and filtering it is not feasible.
- The alternative is to bypass the web player entirely: fetch data via YouTube's internal API, pick a stream, and play it in the native `AVPlayer`. Ads are injected by the official web player, so they never appear in this data flow.

## Architecture options

| Option | How it works | Pros | Cons |
|---|---|---|---|
| **Invidious** (self-hosted) | Server that queries YouTube's InnerTube API, serves HTML and a JSON API, uses PostgreSQL for accounts and subscriptions, optionally proxies video | Simple to host, mature API | Needs a companion service and PO-tokens for current versions; datacenter IPs often blocked |
| **Piped** (self-hosted) | Java backend built on the NewPipe Extractor, separate Vue.js frontend, separate video proxy, PostgreSQL | Clean JSON API, HLS/DASH streams that `AVPlayer` handles well, SponsorBlock built in | More components and subdomains to run; same breakage risk |
| **On-device extraction** (no server) | The app itself sends InnerTube requests via `URLSession`, parses the JSON, handles signature/`n`-parameter decryption using `JavaScriptCore`, and feeds the stream to `AVPlayer` | No server to run, requests come from a residential IP (less blocking), no proxy latency | Maintenance moves into the app; must handle client types and PO-tokens; no SponsorBlock or subscription DB for free |
| **Existing app: Yattee** | Open-source Apple-platform client (incl. tvOS) that supports Invidious and Piped as backends | Fork-able starting point, good for testing instance stability | Still depends on a working backend |
| **AirPlay workaround** | Play in an ad-blocking browser on Mac/iPhone, AirPlay to Apple TV | Zero development | Needs a second device |

## Key technical points
- **InnerTube endpoints:** `/youtubei/v1/player`, `/search`, `/browse`. The client identifies as a specific client type (iOS, Android, TV, web).
- **Stream protection:** Some clients return signed URLs and an `n`-parameter that must be transformed using JavaScript from YouTube's player file. `JavaScriptCore` can run this on tvOS.
- **Stream formats:** HLS is the most convenient for `AVPlayer`. At higher qualities, video and audio are separate adaptive streams and need to be merged or combined manually.
- **Reference implementation:** The NewPipe Extractor (Java) is the best resource for how requests and parsing work, though it can't be used directly in Swift.
- **Candidate Swift libraries:** YouTubeKit, XCDYouTubeKit (tvOS support and maintenance status unverified).

## Main risks
1. **Fragility:** YouTube changes its internal API often, so any solution breaks periodically.
2. **PO-tokens / client types:** Currently the biggest obstacle. Which client works without a Proof-of-Origin token changes frequently.
3. **IP blocking:** Datacenter IPs are heavily restricted; home IPs work better.
4. **ToS:** Violates YouTube's Terms of Service. Practically low risk for private use, but avoid logging in with a main Google account.
5. **Installation:** Without the App Store, sideload via Xcode. A free developer account expires after 7 days; the paid program (99 USD/year) lasts a year.

## Preliminary recommendation
Prototype on-device: a search field, a results list, and playback of one video via a package like YouTubeKit. Keep a home-hosted Piped or Invidious instance as a fallback if the package is unmaintained or stops returning streams.

## Open questions for deeper research
- Which InnerTube client types currently return playable streams without a PO-token, and how stable is that?
- Is YouTubeKit (or a similar package) actively maintained and compatible with tvOS?
- How do Invidious (with companion) and Piped currently handle PO-token generation, and what are the self-hosting requirements?
- How does Yattee's tvOS build handle backends, and how hard is a fork?
- What is the best way to play separate adaptive video and audio streams in `AVPlayer` (for example by composing an `AVMutableComposition` or generating a local HLS manifest)?
- Can SponsorBlock and local subscription storage be integrated cleanly on-device?
- Is `JavaScriptCore` sufficient for current signature and `n`-parameter decryption on tvOS?
