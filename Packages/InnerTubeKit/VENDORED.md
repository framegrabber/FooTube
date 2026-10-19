# InnerTubeKit (vendored)

- Upstream: https://github.com/b5i/YouTubeKit (MIT, see `LICENSE`)
- Version: `v2.8.0`, commit `6532af39da4c1612b0a1af603792419d8fb0e67f` (2026-08-02)
- Why vendored and renamed: alexeichhorn/YouTubeKit (stream extraction) uses the same SwiftPM package identity, product and target name `YouTubeKit`; two packages with one identity cannot coexist in a build graph.

## Changes from upstream (keep this list complete)
1. `Sources/YouTubeKit` → `Sources/InnerTubeKit`; package, product and target renamed to `InnerTubeKit`.
2. `VideoInfosWithDownloadFormatsResponse.swift`: module-qualified `YouTubeKit.VideoDownloadFormat` / `YouTubeKit.AudioOnlyFormat` → `InnerTubeKit.…`.
3. `Package.swift`: platforms set to tvOS 16 / macOS 13 (upstream declares none); tests not vendored.
4. `YouTubeModel.swift`: the channel (`getChannelVideosHeaders`) and channel continuation (`channelContinuationHeaders`) request bodies get `"hl"`/`"gl"` from `selectedLocale`, like the search bodies; upstream omits them, so channel pages and the feed came back in English regardless of locale.

Do not edit vendored sources without adding the change here. To update: re-copy from upstream at a new tag and re-apply the list above.
