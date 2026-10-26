@testable import FooTubeCore
import Foundation
import Testing

/// What the stores write into their sync documents and how they take merged ones back.
@Suite("Store sync documents")
struct SyncStoreDocumentTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let blender = ChannelRef(id: "UCSMOQeBJ2RAnuFungnQOxLg", name: "Blender")
    let first = VideoID("r1jOsar2zV4")!
    let second = VideoID("aiDHXKRxLeQ")!

    private func freshDefaults() -> UserDefaults {
        let suite = "footube-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func summary(_ id: VideoID) -> VideoSummary {
        VideoSummary(id: id, title: id.rawValue, channel: nil, duration: nil, viewCount: nil, published: nil, thumbnail: nil)
    }

    @Test func `unsubscribing leaves a hidden removal marker that re-subscribing clears`() throws {
        let clock = TestClock(start)
        let store = SubscriptionStore(defaults: freshDefaults(), now: clock.now)
        try store.subscribe(blender, avatar: nil)
        clock.advance(by: 10)
        try store.unsubscribe(blender.id)

        #expect(store.channels().isEmpty)
        #expect(!store.isSubscribed(blender.id))
        #expect(store.document().entries == [SubscriptionRecord(id: blender.id, name: "Blender", avatar: nil, changedAt: start + 10, removedAt: start + 10)])

        clock.advance(by: 10)
        try store.subscribe(blender, avatar: nil)
        #expect(store.isSubscribed(blender.id))
        #expect(store.document().entries == [SubscriptionRecord(id: blender.id, name: "Blender", avatar: nil, changedAt: start + 20)])
    }

    @Test func `subscribing again with the same data is not a change`() throws {
        let clock = TestClock(start)
        let store = SubscriptionStore(defaults: freshDefaults(), now: clock.now)
        try store.subscribe(blender, avatar: nil)
        clock.advance(by: 10)
        try store.subscribe(blender, avatar: nil)
        #expect(store.document().entries.map(\.changedAt) == [start])
        try store.subscribe(ChannelRef(id: blender.id, name: "Blender Studio"), avatar: nil)
        #expect(store.document().entries.map(\.changedAt) == [start + 10])
    }

    @Test func `removing from watch later leaves a hidden marker that re-adding clears`() throws {
        let clock = TestClock(start)
        let store = WatchLaterStore(defaults: freshDefaults(), now: clock.now)
        try store.add(summary(first))
        clock.advance(by: 10)
        try store.remove(first)
        #expect(store.items().isEmpty)
        #expect(!store.contains(first))
        #expect(store.document().entries.map(\.removedAt) == [start + 10])

        clock.advance(by: 10)
        try store.add(summary(first))
        #expect(store.items().map(\.id) == [first])
        #expect(store.document().entries == [WatchLaterRecord(video: summary(first), addedAt: start + 20, changedAt: start + 20)])
    }

    @Test func `clearing watch later marks every video removed`() throws {
        let clock = TestClock(start)
        let store = WatchLaterStore(defaults: freshDefaults(), now: clock.now)
        try store.add(summary(first))
        try store.add(summary(second))
        clock.advance(by: 10)
        store.clear()
        #expect(store.items().isEmpty)
        #expect(store.document().entries.count == 2)
        #expect(store.document().entries.allSatisfy { $0.removedAt == start + 10 && $0.changedAt == start + 10 })
    }

    @Test func `videos added within the same millisecond keep their order`() throws {
        let store = WatchLaterStore(defaults: freshDefaults(), now: { Date(timeIntervalSince1970: 1_800_000_000) })
        try store.add(summary(first))
        try store.add(summary(second))
        try store.add(summary(first))
        #expect(store.items().map(\.id) == [first, second])
    }

    @Test func `saving drops removal markers older than 90 days`() throws {
        let clock = TestClock(start)
        let store = WatchLaterStore(defaults: freshDefaults(), now: clock.now)
        try store.add(summary(first))
        try store.remove(first)
        clock.advance(by: SyncMerge.markerLifetime)
        try store.add(summary(second))
        #expect(store.document().entries.count == 2)
        clock.advance(by: 1)
        try store.remove(second)
        #expect(store.document().entries.map(\.video.id) == [second])
    }

    @Test func `clearing history records when, so other devices drop older entries too`() throws {
        let history = WatchHistory(defaults: freshDefaults(), now: { Date(timeIntervalSince1970: 1_800_000_100) })
        try history.record(first, position: 100, duration: 600, at: start)
        history.clear()
        #expect(history.entries().isEmpty)
        #expect(history.document() == HistoryDocument(clearedAt: start + 100, entries: []))

        let remote = HistoryDocument(entries: [WatchEntry(videoID: first, position: 100, duration: 600, updatedAt: start, watched: false)])
        #expect(merge(history.document(), remote, lastSyncAt: nil, now: start + 200).entries.isEmpty)
    }

    @Test func `recording keeps clearedAt`() throws {
        let history = WatchHistory(defaults: freshDefaults(), now: { Date(timeIntervalSince1970: 1_800_000_000) })
        history.clear()
        try history.record(first, position: 100, duration: 600, at: start + 10)
        #expect(history.document().clearedAt == start)
        #expect(history.entries().map(\.videoID) == [first])
    }

    @Test func `restoring default skip settings is a change`() {
        let clock = TestClock(start)
        let store = SkipSettingsStore(defaults: freshDefaults(), now: clock.now)
        #expect(store.document().changedAt == nil)
        var settings = SkipSettings.default
        settings.set(.off, for: .sponsor)
        store.save(settings)
        clock.advance(by: 10)
        store.save(.default)
        #expect(store.document() == SkipSettingsDocument(changedAt: start + 10, overrides: [:]))
        #expect(store.load() == .default)
    }

    @Test func `replaced documents are what readers see`() throws {
        let defaults = freshDefaults()
        let subscriptions = SubscriptionStore(defaults: defaults)
        try subscriptions.replace(SubscriptionsDocument(entries: [
            SubscriptionRecord(id: "UC2", name: "Zed", avatar: nil, changedAt: start),
            SubscriptionRecord(id: "UC1", name: "Gone", avatar: nil, changedAt: start, removedAt: start),
            SubscriptionRecord(id: "UC3", name: "Alpha", avatar: nil, changedAt: start),
        ]))
        #expect(subscriptions.channels().map(\.name) == ["Alpha", "Zed"])
        #expect(!subscriptions.isSubscribed("UC1"))

        let watchLater = WatchLaterStore(defaults: defaults)
        try watchLater.replace(WatchLaterDocument(entries: [
            WatchLaterRecord(video: summary(first), addedAt: start, changedAt: start),
            WatchLaterRecord(video: summary(second), addedAt: start + 1, changedAt: start + 1),
        ]))
        #expect(watchLater.items().map(\.id) == [second, first])

        let history = WatchHistory(defaults: defaults)
        let entry = WatchEntry(videoID: first, position: 125, duration: 600, updatedAt: start, watched: true)
        try history.replace(HistoryDocument(entries: [entry]))
        #expect(history.entry(for: first) == entry)

        let settings = SkipSettingsStore(defaults: defaults)
        try settings.replace(SkipSettingsDocument(changedAt: start, overrides: ["intro": "off"]))
        #expect(settings.load().behavior(for: .intro) == .off)
    }

    @Test func `the stored document is the canonical encoding the Worker gets`() throws {
        let defaults = freshDefaults()
        let store = SubscriptionStore(defaults: defaults, now: { Date(timeIntervalSince1970: 1_800_000_000.5) })
        try store.subscribe(blender, avatar: URL(string: "https://yt3.ggpht.com/a.jpg"))
        let stored = try #require(defaults.data(forKey: "subscriptions.v2"))
        #expect(try stored == SyncCoding.encode(store.document()))
        #expect(String(decoding: stored, as: UTF8.self)
            == #"{"entries":[{"avatar":"https://yt3.ggpht.com/a.jpg","changedAt":"2027-01-15T08:00:00.500Z","id":"UCSMOQeBJ2RAnuFungnQOxLg","name":"Blender"}],"format":1}"#)
    }
}
