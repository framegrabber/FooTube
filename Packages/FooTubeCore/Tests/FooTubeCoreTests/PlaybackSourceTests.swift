import AVFoundation
import FooTubeCore
import Foundation
import Testing

@Suite("PlaybackSource serves the filtered playlist to AVFoundation")
struct PlaybackSourceTests {
    @Test func `AVFoundation reads the filtered variants through the resource loader`() async throws {
        let url = try #require(Bundle.module.url(forResource: "master-bbb", withExtension: "m3u8", subdirectory: "Fixtures"))
        let filtered = try #require(HLSMasterPlaylist.filtered(String(contentsOf: url, encoding: .utf8), for: .appleTVHD))
        let stream = try ResolvedStream(
            videoID: #require(VideoID("a_b-c_d-e_f")),
            url: #require(URL(string: "https://example.invalid/master.m3u8")),
            kind: .hls(playlist: filtered.text, variantCount: filtered.variantCount, maxHeight: filtered.maxHeight),
        )
        let source = PlaybackSource(stream: stream)

        let variants = try await source.asset.load(.variants)
        #expect(variants.count == 7)
        #expect(variants.compactMap { $0.videoAttributes?.presentationSize.height }.max() == 1080)
        withExtendedLifetime(source) {}
    }
}
