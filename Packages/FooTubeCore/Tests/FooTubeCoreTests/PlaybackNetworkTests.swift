import AVFoundation
import FooTubeCore
import Foundation
import Testing

/// Hits real YouTube and AVFoundation. Opt-in like ResolverNetworkTests.
@Suite(
    "Filtered HLS plays in AVPlayer",
    .enabled(if: ProcessInfo.processInfo.environment["FOOTUBE_NETWORK_TESTS"] == "1"),
)
struct PlaybackNetworkTests {
    @Test func `filtered HLS master becomes ready to play and renders frames`() async throws {
        let id = try #require(VideoID("aqz-KE-bpKQ"))
        let stream = try await YouTubeKitResolver().resolve(id)
        guard case .hls = stream.kind else {
            Issue.record("expected HLS, got \(stream.summary)")
            return
        }
        let source = PlaybackSource(stream: stream)
        #expect(try await source.asset.load(.isPlayable))

        let item = AVPlayerItem(asset: source.asset)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.play()

        var waited = 0
        while item.status == .unknown || player.currentTime().seconds < 2, waited < 200 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        print("RESULT status=\(item.status.rawValue) time=\(player.currentTime().seconds) size=\(item.presentationSize) bitrate=\(item.accessLog()?.events.last?.indicatedBitrate ?? 0) error=\(String(describing: item.error))")
        #expect(item.status == .readyToPlay)
        #expect(player.currentTime().seconds >= 2)
        #expect(item.presentationSize.height > 0)
        player.pause()
        withExtendedLifetime(source) {}
    }
}
