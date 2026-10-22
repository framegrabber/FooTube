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
}
