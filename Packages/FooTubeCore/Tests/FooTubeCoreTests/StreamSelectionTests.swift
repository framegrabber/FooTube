import FooTubeCore
import Foundation
import Testing

private func candidate(
    itag: Int,
    video: VideoCodec?,
    audio: AudioCodec?,
    height: Int?,
    bitrate: Int? = nil,
) -> StreamCandidate {
    StreamCandidate(
        url: URL(string: "https://example.invalid/\(itag)")!,
        itag: itag,
        videoCodec: video,
        audioCodec: audio,
        height: height,
        bitrate: bitrate,
    )
}

@Suite("Muxed stream selection for Apple TV HD")
struct StreamSelectionTests {
    let profile = DecodeProfile.appleTVHD

    @Test func `picks highest muxed H 264 with AAC`() {
        let streams = [
            candidate(itag: 18, video: .h264(profileLevelID: "42001E"), audio: .aac, height: 360),
            candidate(itag: 22, video: .h264(profileLevelID: "64001F"), audio: .aac, height: 720),
            candidate(itag: 137, video: .h264(profileLevelID: "640028"), audio: nil, height: 1080),
            candidate(itag: 140, video: nil, audio: .aac, height: nil),
        ]
        #expect(StreamSelector.bestMuxed(streams, for: profile)?.itag == 22)
    }

    @Test func `rejects codecs the device cannot decode`() {
        let streams = [
            candidate(itag: 1, video: .other("vp09.00.40.08"), audio: .aac, height: 1080),
            candidate(itag: 2, video: .other("av01.0.08M.08"), audio: .aac, height: 1080),
            candidate(itag: 3, video: .h264(profileLevelID: "64001F"), audio: .other("opus"), height: 720),
            candidate(itag: 18, video: .h264(profileLevelID: "42001E"), audio: .aac, height: 360),
        ]
        #expect(StreamSelector.bestMuxed(streams, for: profile)?.itag == 18)
    }

    @Test func `rejects resolution above device maximum`() {
        let streams = [
            candidate(itag: 1, video: .h264(profileLevelID: "640033"), audio: .aac, height: 2160),
            candidate(itag: 18, video: .h264(profileLevelID: "42001E"), audio: .aac, height: 360),
        ]
        #expect(StreamSelector.bestMuxed(streams, for: profile)?.itag == 18)
    }

    @Test func `rejects H 264 level above device maximum`() {
        // Level 5.0 (0x32) exceeds the Apple TV HD's High Profile level 4.2 (0x2A).
        let streams = [
            candidate(itag: 1, video: .h264(profileLevelID: "640032"), audio: .aac, height: 1080),
            candidate(itag: 2, video: .h264(profileLevelID: "64002A"), audio: .aac, height: 1080),
        ]
        #expect(StreamSelector.bestMuxed(streams, for: profile)?.itag == 2)
    }

    @Test func `prefers higher bitrate at equal height`() {
        let streams = [
            candidate(itag: 1, video: .h264(profileLevelID: "64001F"), audio: .aac, height: 720, bitrate: 1_000_000),
            candidate(itag: 2, video: .h264(profileLevelID: "64001F"), audio: .aac, height: 720, bitrate: 2_000_000),
        ]
        #expect(StreamSelector.bestMuxed(streams, for: profile)?.itag == 2)
    }

    @Test func `returns nil when nothing qualifies`() {
        let streams = [
            candidate(itag: 137, video: .h264(profileLevelID: "640028"), audio: nil, height: 1080),
            candidate(itag: 251, video: nil, audio: .other("opus"), height: nil),
        ]
        #expect(StreamSelector.bestMuxed(streams, for: profile) == nil)
    }

    @Test(arguments: [
        ("avc1.64002A", VideoCodec.h264(profileLevelID: "64002A")),
        ("avc1.4d401f", VideoCodec.h264(profileLevelID: "4D401F")),
        ("vp09.00.40.08", VideoCodec.other("vp09.00.40.08")),
        ("avc1", VideoCodec.other("avc1")),
    ])
    func `parses video codec strings`(raw: String, expected: VideoCodec) {
        #expect(VideoCodec(codecString: raw) == expected)
    }
}
