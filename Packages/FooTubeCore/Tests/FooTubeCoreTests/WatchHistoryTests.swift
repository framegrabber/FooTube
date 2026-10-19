@testable import FooTubeCore
import Foundation
import Testing

@Suite("Local watch history")
struct WatchHistoryTests {
    let video = VideoID("r1jOsar2zV4")!
    let other = VideoID("aiDHXKRxLeQ")!

    private func freshDefaults() -> UserDefaults {
        let suite = "footube-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func `resumes only between the first 10 s and the last 30 s`() throws {
        let history = WatchHistory(defaults: freshDefaults())
        #expect(history.resumePosition(for: video) == nil)

        try history.record(video, position: 8, duration: 600)
        #expect(history.resumePosition(for: video) == nil)
        try history.record(video, position: 125.5, duration: 600)
        #expect(history.resumePosition(for: video) == 125.5)
        try history.record(video, position: 575, duration: 600)
        #expect(history.resumePosition(for: video) == nil)
    }

    @Test func `counts as watched at 90 percent and stays watched when re-watching`() throws {
        let history = WatchHistory(defaults: freshDefaults())
        let partial = try #require(try history.record(video, position: 300, duration: 600))
        #expect(!partial.watched)
        #expect(partial.progress == 0.5)

        let almost = try #require(try history.record(video, position: 539, duration: 600))
        #expect(!almost.watched)
        let watched = try #require(try history.record(video, position: 540, duration: 600))
        #expect(watched.watched)
        #expect(watched.progress == 1)

        let rewatch = try #require(try history.record(video, position: 60, duration: 600))
        #expect(rewatch.watched)
        #expect(rewatch.progress == 1)
        #expect(history.resumePosition(for: video) == 60)
    }

    @Test func `reaching the end marks watched and restarts next time`() throws {
        let history = WatchHistory(defaults: freshDefaults())
        // A long video ends with 10 % (6 min) of credits the player still plays through.
        let entry = try #require(try history.record(video, position: 3000, duration: 3600, reachedEnd: true))
        #expect(entry.watched)
        #expect(entry.position == 3600)
        #expect(history.resumePosition(for: video) == nil)
    }

    @Test func `live streams and unknown durations are not recorded`() throws {
        let history = WatchHistory(defaults: freshDefaults())
        #expect(try history.record(video, position: 120, duration: .nan) == nil)
        #expect(try history.record(video, position: 120, duration: .infinity) == nil)
        #expect(try history.record(video, position: 120, duration: 0) == nil)
        #expect(try history.record(video, position: .nan, duration: 600) == nil)
        #expect(history.entries().isEmpty)
    }

    @Test func `positions are clamped to the video`() throws {
        let history = WatchHistory(defaults: freshDefaults())
        let before = try #require(try history.record(video, position: -3, duration: 600))
        #expect(before.position == 0)
        #expect(before.progress == 0)
        let after = try #require(try history.record(video, position: 700, duration: 600))
        #expect(after.position == 600)
        #expect(after.watched)
    }

    @Test func `history survives a new store instance and keeps one entry per video, newest first`() throws {
        let defaults = freshDefaults()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try WatchHistory(defaults: defaults).record(video, position: 100, duration: 600, at: start)
        try WatchHistory(defaults: defaults).record(other, position: 50, duration: 300, at: start + 10)
        try WatchHistory(defaults: defaults).record(video, position: 200, duration: 600, at: start + 20)

        let entries = WatchHistory(defaults: defaults).entries()
        #expect(entries.map(\.videoID) == [video, other])
        #expect(entries.first == WatchEntry(videoID: video, position: 200, duration: 600, updatedAt: start + 20, watched: false))
        #expect(WatchHistory(defaults: defaults).entry(for: other)?.position == 50)
    }

    @Test func `keeps only the 500 most recently played videos`() throws {
        let history = WatchHistory(defaults: freshDefaults())
        let ids = try (0 ... WatchHistory.capacity).map { try #require(VideoID(String(format: "vid%08d", $0))) }
        for id in ids {
            try history.record(id, position: 30, duration: 600)
        }
        let entries = history.entries()
        #expect(entries.count == WatchHistory.capacity)
        #expect(entries.first?.videoID == ids.last)
        #expect(history.entry(for: ids[0]) == nil)
        #expect(history.entry(for: ids[1]) != nil)
    }

    @Test func `unreadable stored data counts as empty history and is replaced on the next save`() throws {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: "watchHistory.v1")
        let history = WatchHistory(defaults: defaults)
        #expect(history.entries().isEmpty)
        try history.record(video, position: 100, duration: 600)
        #expect(history.entries().map(\.videoID) == [video])
    }

    private func summary(_ id: VideoID, title: String) -> VideoSummary {
        VideoSummary(id: id, title: title, channel: nil, duration: nil, viewCount: nil, published: nil, thumbnail: nil)
    }

    @Test func `keeps the stored summary when a later record has none`() throws {
        let history = WatchHistory(defaults: freshDefaults())
        try history.record(video, position: 100, duration: 600, video: summary(video, title: "First"))
        let kept = try #require(try history.record(video, position: 200, duration: 600))
        #expect(kept.video?.title == "First")
        #expect(history.entry(for: video)?.video?.title == "First")

        try history.record(video, position: 300, duration: 600, video: summary(video, title: "Renamed"))
        #expect(history.entry(for: video)?.video?.title == "Renamed")
    }

    @Test func `decodes entries stored without a summary`() throws {
        let defaults = freshDefaults()
        let legacy = """
        [{"videoID":"r1jOsar2zV4","position":125.5,"duration":600,"updatedAt":800000000,"watched":false}]
        """
        defaults.set(Data(legacy.utf8), forKey: "watchHistory.v1")
        let history = WatchHistory(defaults: defaults)
        let entry = try #require(history.entries().first)
        #expect(entry.videoID == video)
        #expect(entry.position == 125.5)
        #expect(entry.video == nil)

        try history.record(video, position: 130, duration: 600, video: summary(video, title: "Now known"))
        #expect(history.entry(for: video)?.video?.title == "Now known")
    }
}
