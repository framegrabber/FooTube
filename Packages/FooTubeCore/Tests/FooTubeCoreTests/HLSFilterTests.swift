import FooTubeCore
import Foundation
import Testing

@Suite("HLS master playlist filtering for Apple TV HD")
struct HLSFilterTests {
    let master: String = {
        let url = Bundle.module.url(forResource: "master-bbb", withExtension: "m3u8", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }()

    private func variants(_ text: String) -> [String] {
        text.split(separator: "\n").filter { $0.hasPrefix("#EXT-X-STREAM-INF") }.map(String.init)
    }

    @Test func `keeps only decodable H 264 variants`() throws {
        let filtered = try #require(HLSMasterPlaylist.filtered(master, for: .appleTVHD))
        let kept = variants(filtered.text)
        #expect(kept.count == 7)
        #expect(kept.allSatisfy { $0.contains("CODECS=\"avc1.") })
        #expect(filtered.maxHeight == 1080)
        #expect(filtered.variantCount == 7)
    }

    @Test func `each kept variant keeps its own URI, 720p first, VP9 URIs gone`() throws {
        let lines = try #require(HLSMasterPlaylist.filtered(master, for: .appleTVHD)).text
            .split(separator: "\n").map(String.init)
        let uris = lines.filter { $0.hasPrefix("https://") }
        #expect(uris == [8, 3, 4, 5, 6, 7, 9].map { "https://example.invalid/playlist/\($0).m3u8" })
        let firstVariant = try #require(lines.firstIndex { $0.hasPrefix("#EXT-X-STREAM-INF") })
        #expect(lines[firstVariant].contains("RESOLUTION=1280x720"))
        #expect(lines[firstVariant + 1] == "https://example.invalid/playlist/8.m3u8")
    }

    @Test func `CRLF line endings are handled like LF`() throws {
        let crlf = master.replacingOccurrences(of: "\n", with: "\r\n")
        let filtered = try #require(HLSMasterPlaylist.filtered(crlf, for: .appleTVHD))
        #expect(filtered.variantCount == 7)
    }

    @Test func `I-frame playlists the device cannot decode are dropped`() throws {
        let text = """
        #EXTM3U
        #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=1,CODECS="vp09.00.40.08",RESOLUTION=1920x1080,URI="https://example.invalid/iframe-vp9.m3u8"
        #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=1,CODECS="avc1.640028",RESOLUTION=1920x1080,URI="https://example.invalid/iframe-h264.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=1,CODECS="avc1.640028,mp4a.40.2",RESOLUTION=1920x1080
        https://example.invalid/h264.m3u8
        """
        let filtered = try #require(HLSMasterPlaylist.filtered(text, for: .appleTVHD)).text
        #expect(!filtered.contains("iframe-vp9"))
        #expect(filtered.contains("iframe-h264"))
    }

    @Test func `non-AAC audio or subtitle codecs do not disqualify an H 264 variant`() throws {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1,CODECS="avc1.640028,ec-3,wvtt",RESOLUTION=1920x1080
        https://example.invalid/h264.m3u8
        """
        #expect(try #require(HLSMasterPlaylist.filtered(text, for: .appleTVHD)).variantCount == 1)
    }

    @Test func `keeps header and rendition groups`() throws {
        let text = try #require(HLSMasterPlaylist.filtered(master, for: .appleTVHD)).text
        #expect(text.hasPrefix("#EXTM3U\n"))
        #expect(text.components(separatedBy: "#EXT-X-MEDIA:").count - 1 == 2)
    }

    @Test func `respects lower height limit`() throws {
        let profile = DecodeProfile(maxHeight: 720, maxH264Level: 42)
        let filtered = try #require(HLSMasterPlaylist.filtered(master, for: profile))
        #expect(filtered.maxHeight == 720)
        #expect(!filtered.text.contains("RESOLUTION=1920x1080"))
    }

    @Test func `portrait resolution uses smaller dimension`() throws {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1,CODECS="avc1.64002A,mp4a.40.2",RESOLUTION=1080x1920
        https://example.invalid/portrait.m3u8
        """
        #expect(try #require(HLSMasterPlaylist.filtered(text, for: .appleTVHD)).maxHeight == 1080)
    }

    @Test func `returns nil when no variant is decodable`() {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1,CODECS="vp09.00.40.08,mp4a.40.2",RESOLUTION=1920x1080
        https://example.invalid/vp9.m3u8
        """
        #expect(HLSMasterPlaylist.filtered(text, for: .appleTVHD) == nil)
    }

    @Test func `ignores supplemental codecs attribute`() throws {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:SUPPLEMENTAL-CODECS="vp09.00.40.08",BANDWIDTH=1,CODECS="avc1.640028,mp4a.40.2",RESOLUTION=1920x1080
        https://example.invalid/h264.m3u8
        """
        #expect(try #require(HLSMasterPlaylist.filtered(text, for: .appleTVHD)).variantCount == 1)
    }

    @Test func `lists the best variant at or below 720p first so playback starts sharp`() throws {
        let text = try #require(HLSMasterPlaylist.filtered(master, for: .appleTVHD)).text
        let first = try #require(variants(text).first)
        #expect(first.contains("RESOLUTION=1280x720"))
    }
}
