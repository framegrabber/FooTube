@testable import FooTubeCore
import Foundation
import Testing

@Suite("Watch later")
struct WatchLaterTests {
    let first = VideoID("r1jOsar2zV4")!
    let second = VideoID("aiDHXKRxLeQ")!

    private func freshDefaults() -> UserDefaults {
        let suite = "footube-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func summary(_ id: VideoID, title: String? = nil) -> VideoSummary {
        VideoSummary(id: id, title: title ?? id.rawValue, channel: nil, duration: nil, viewCount: nil, published: nil, thumbnail: nil)
    }

    @Test func `adds, contains and removes videos, newest first`() throws {
        let store = WatchLaterStore(defaults: freshDefaults())
        #expect(store.items().isEmpty)
        #expect(!store.contains(first))

        try store.add(summary(first))
        try store.add(summary(second))
        #expect(store.items().map(\.id) == [second, first])
        #expect(store.contains(first))

        try store.remove(first)
        #expect(store.items().map(\.id) == [second])
        #expect(!store.contains(first))
        try store.remove(first)
        #expect(store.items().map(\.id) == [second])
    }

    @Test func `re-adding moves the video to the front without duplicating it`() throws {
        let store = WatchLaterStore(defaults: freshDefaults())
        try store.add(summary(first, title: "Old"))
        try store.add(summary(second))
        try store.add(summary(first, title: "New"))
        #expect(store.items().map(\.id) == [first, second])
        #expect(store.items().first?.title == "New")
    }

    @Test func `persists across instances`() throws {
        let defaults = freshDefaults()
        try WatchLaterStore(defaults: defaults).add(summary(first))
        #expect(WatchLaterStore(defaults: defaults).items().map(\.id) == [first])
    }

    @Test func `corrupt data reads as empty`() throws {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: "watchLater.v1")
        let store = WatchLaterStore(defaults: defaults)
        #expect(store.items().isEmpty)
        try store.add(summary(first))
        #expect(store.items().map(\.id) == [first])
    }

    @Test func `clearing removes every video, also for a new store instance`() throws {
        let defaults = freshDefaults()
        let store = WatchLaterStore(defaults: defaults)
        try store.add(summary(first))
        try store.add(summary(second))
        store.clear()
        #expect(store.items().isEmpty)
        #expect(WatchLaterStore(defaults: defaults).items().isEmpty)
    }

    @Test func `a removal keeps only the video ID, so the marker holds no title or thumbnail`() throws {
        let defaults = freshDefaults()
        let store = WatchLaterStore(defaults: defaults)
        let thumbnail = URL(string: "https://i.ytimg.com/vi/\(first.rawValue)/hqdefault.jpg")
        let full = VideoSummary(id: first, title: String(repeating: "t", count: 5000), channel: ChannelRef(id: "UC1", name: "C"), duration: "1:00", viewCount: "1", published: "1d", thumbnail: thumbnail)
        try store.add(full)
        try store.add(VideoSummary(id: second, title: "Second", channel: nil, duration: nil, viewCount: nil, published: nil, thumbnail: thumbnail))
        try store.remove(first)
        store.clear()
        let markers = store.document().entries
        #expect(markers.map(\.video) == [second, first].map { VideoSummary(id: $0, title: "", channel: nil, duration: nil, viewCount: nil, published: nil, thumbnail: nil) })
        #expect(markers.allSatisfy { $0.removedAt != nil })
    }

    @Test func `adding beyond 1,000 videos drops the oldest added`() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let store = WatchLaterStore(defaults: freshDefaults(), now: { start })
        let ids = (0 ..< WatchLaterStore.capacity).map { VideoID(String(format: "v%010d", $0))! }
        // Index 0 added first (oldest); a removal marker older than all of them doesn't count.
        let records = ids.enumerated().map { index, id in
            WatchLaterRecord(video: summary(id), addedAt: start - 2000 + TimeInterval(index), changedAt: start - 2000 + TimeInterval(index))
        } + [WatchLaterRecord(video: summary(second), addedAt: start - 5000, changedAt: start - 5000, removedAt: start - 5000)]
        try store.replace(WatchLaterDocument(entries: records))

        try store.add(summary(first))
        let items = store.items()
        #expect(WatchLaterStore.capacity == 1000)
        #expect(items.count == 1000)
        #expect(items.first?.id == first)
        #expect(!items.contains { $0.id == ids[0] })
        #expect(items.last?.id == ids[1])
        #expect(store.document().entries.contains { $0.video.id == second && $0.removedAt != nil })
    }
}
