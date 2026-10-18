@testable import FooTubeCore
import Foundation
import Testing

@Suite("Subscriptions feed")
struct FeedTests {
    @Test(arguments: [
        ("12 seconds ago", 12),
        ("1 minute ago", 60),
        ("5 hours ago", 18000),
        ("1 day ago", 86400),
        ("3 days ago", 259_200),
        ("2 weeks ago", 1_209_600),
        ("1 month ago", 2_592_000),
        ("4 years ago", 126_144_000),
        ("Streamed 2 hours ago", 7200),
        ("Premiered 6 days ago", 518_400),
    ] as [(String, Double)])
    func `parses YouTube relative ages`(text: String, seconds: Double) {
        #expect(FeedMerger.age(of: text) == seconds)
    }

    @Test(arguments: ["", "Scheduled for 10/20/26", "vor 3 Tagen", "LIVE"])
    func `unknown age text yields nil`(text: String) {
        #expect(FeedMerger.age(of: text) == nil)
    }

    private func video(_ id: String, _ published: String?) -> VideoSummary {
        VideoSummary(id: VideoID(id)!, title: id, channel: nil, duration: nil, viewCount: nil, published: published, thumbnail: nil)
    }

    @Test func `merges channels newest first, unknown ages last, duplicates removed`() {
        let channelA = [video("aaaaaaaaaaa", "2 days ago"), video("bbbbbbbbbbb", "3 weeks ago")]
        let channelB = [video("ccccccccccc", "5 hours ago"), video("ddddddddddd", nil), video("aaaaaaaaaaa", "2 days ago")]
        let merged = FeedMerger.merge([channelA, channelB], limit: 10)
        #expect(merged.map(\.id.rawValue) == ["ccccccccccc", "aaaaaaaaaaa", "bbbbbbbbbbb", "ddddddddddd"])
    }

    @Test func `merge keeps only the newest videos up to the limit`() {
        let videos = [video("aaaaaaaaaaa", "1 day ago"), video("bbbbbbbbbbb", "1 hour ago"), video("ccccccccccc", "1 year ago")]
        #expect(FeedMerger.merge([videos], limit: 2).map(\.id.rawValue) == ["bbbbbbbbbbb", "aaaaaaaaaaa"])
    }

    @Test func `cache round-trips the feed and its fetch date`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "feedcache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FeedCache(directory: directory)
        #expect(cache.load() == nil)
        let snapshot = FeedSnapshot(fetchedAt: Date(timeIntervalSince1970: 1_800_000_000), items: [video("aaaaaaaaaaa", "1 day ago")])
        try cache.save(snapshot)
        #expect(cache.load() == snapshot)
    }
}
