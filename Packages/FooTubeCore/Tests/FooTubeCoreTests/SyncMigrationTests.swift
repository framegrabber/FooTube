@testable import FooTubeCore
import Foundation
import Testing

@Suite("Migration of v1 stores to sync documents")
struct SyncMigrationTests {
    static let migrationTime = Date(timeIntervalSince1970: 1_800_000_000)
    let clock: @Sendable () -> Date = { SyncMigrationTests.migrationTime }

    private func freshDefaults() -> UserDefaults {
        let suite = "footube-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// v1 data as the previous build wrote it (`Fixtures/migration`).
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/migration"))
        return try Data(contentsOf: url)
    }

    @Test func `subscriptions keep names and avatars and get the migration time as changedAt`() throws {
        let defaults = freshDefaults()
        try defaults.set(fixture("subscriptions-v1"), forKey: "subscriptions.v1")
        let store = SubscriptionStore(defaults: defaults, now: clock)

        #expect(store.channels() == [
            Subscription(id: "UCSMOQeBJ2RAnuFungnQOxLg", name: "Blender", avatar: nil),
            Subscription(id: "UCvlj0IzjSnNoduQF0l3VGng", name: "Kurzgesagt", avatar: URL(string: "https://yt3.ggpht.com/ksp=s88")),
            Subscription(id: "UCuAXFkgsw1L7xaCfnd5JJOw", name: "Rick Astley", avatar: URL(string: "https://yt3.ggpht.com/rick=s88")),
        ])
        #expect(store.document().entries.allSatisfy { $0.changedAt == Self.migrationTime && $0.removedAt == nil })
        #expect(defaults.object(forKey: "subscriptions.v1") == nil)
        #expect(defaults.data(forKey: "subscriptions.v2") != nil)
        #expect(SubscriptionStore(defaults: defaults).channels().count == 3)
    }

    @Test func `watch later keeps order and summaries, addedAt one second apart`() throws {
        let defaults = freshDefaults()
        let v1 = try fixture("watchLater-v1")
        defaults.set(v1, forKey: "watchLater.v1")
        let store = WatchLaterStore(defaults: defaults, now: clock)

        #expect(try store.items() == JSONDecoder().decode([VideoSummary].self, from: v1))
        #expect(store.items().map(\.id.rawValue) == ["aiDHXKRxLeQ", "r1jOsar2zV4", "dQw4w9WgXcQ"])
        #expect(store.items().first?.thumbnail?.absoluteString == "https://i.ytimg.com/vi/aiDHXKRxLeQ/hqdefault.jpg")
        #expect(store.document().entries.map(\.addedAt) == [Self.migrationTime, Self.migrationTime - 1, Self.migrationTime - 2])
        #expect(store.document().entries.allSatisfy { $0.changedAt == $0.addedAt && $0.removedAt == nil })
        #expect(defaults.object(forKey: "watchLater.v1") == nil)
    }

    @Test func `history keeps order, positions, watched marks, summaries and updatedAt`() throws {
        let defaults = freshDefaults()
        let v1 = try fixture("watchHistory-v1")
        defaults.set(v1, forKey: "watchHistory.v1")
        let history = WatchHistory(defaults: defaults, now: clock)

        let expected = try JSONDecoder().decode([WatchEntry].self, from: v1)
        #expect(history.entries() == expected)
        #expect(history.entries().map(\.position) == [1234.5, 600, 30])
        #expect(history.entries().map(\.watched) == [false, true, true])
        #expect(history.entries().map(\.video?.title) == ["Sprite Fright", nil, "Never Gonna Give You Up"])
        #expect(history.entries().first?.updatedAt == Date(timeIntervalSinceReferenceDate: 800_000_300.25))
        #expect(try history.resumePosition(for: #require(VideoID("aiDHXKRxLeQ"))) == 1234.5)
        #expect(history.document().clearedAt == nil)
        #expect(defaults.object(forKey: "watchHistory.v1") == nil)
        #expect(WatchHistory(defaults: defaults).entries() == expected)
    }

    @Test func `changed skip settings survive with the migration time as changedAt`() throws {
        let defaults = freshDefaults()
        let raw = try JSONDecoder().decode([String: String].self, from: fixture("skipSettings-v1"))
        defaults.set(raw, forKey: "skipSettings.v1")
        let store = SkipSettingsStore(defaults: defaults, now: clock)

        let settings = store.load()
        #expect(settings.behavior(for: .sponsor) == .showButton)
        #expect(settings.behavior(for: .musicOfftopic) == .off)
        #expect(settings.behavior(for: .filler) == .skipAutomatically)
        #expect(settings.behavior(for: .intro) == .showButton)
        #expect(store.document().changedAt == Self.migrationTime)
        #expect(store.document().overrides == ["sponsor": "showButton", "music_offtopic": "off", "filler": "skipAutomatically"])
        #expect(defaults.object(forKey: "skipSettings.v1") == nil)
    }

    @Test func `default skip settings stay never changed`() {
        let defaults = freshDefaults()
        defaults.set(["sponsor": "skipAutomatically"], forKey: "skipSettings.v1")
        let store = SkipSettingsStore(defaults: defaults, now: clock)
        #expect(store.document() == .empty)
        #expect(defaults.object(forKey: "skipSettings.v1") == nil)
    }

    @Test func `unreadable v1 data becomes an empty document and the v1 key is removed`() {
        let defaults = freshDefaults()
        let junk = Data("not json".utf8)
        for key in ["subscriptions.v1", "watchLater.v1", "watchHistory.v1", "skipSettings.v1"] {
            defaults.set(junk, forKey: key)
        }
        #expect(SubscriptionStore(defaults: defaults, now: clock).document() == .empty)
        #expect(WatchLaterStore(defaults: defaults, now: clock).document() == .empty)
        #expect(WatchHistory(defaults: defaults, now: clock).document() == .empty)
        #expect(SkipSettingsStore(defaults: defaults, now: clock).document() == .empty)
        for key in ["subscriptions.v1", "watchLater.v1", "watchHistory.v1", "skipSettings.v1"] {
            #expect(defaults.object(forKey: key) == nil)
        }
    }

    @Test func `migration runs once and never overwrites an existing v2 document`() throws {
        let defaults = freshDefaults()
        try defaults.set(fixture("subscriptions-v1"), forKey: "subscriptions.v1")
        let store = SubscriptionStore(defaults: defaults, now: clock)
        try store.unsubscribe("UCSMOQeBJ2RAnuFungnQOxLg")
        #expect(store.channels().count == 2)

        // A stale v1 key (e.g. written by an older build installed in between) doesn't win.
        try defaults.set(fixture("subscriptions-v1"), forKey: "subscriptions.v1")
        #expect(store.channels().count == 2)
        #expect(defaults.object(forKey: "subscriptions.v1") == nil)
    }

    @Test func `a store without v1 or v2 data starts empty and writes nothing on reading`() {
        let defaults = freshDefaults()
        #expect(SubscriptionStore(defaults: defaults).channels().isEmpty)
        #expect(WatchLaterStore(defaults: defaults).items().isEmpty)
        #expect(WatchHistory(defaults: defaults).entries().isEmpty)
        #expect(SkipSettingsStore(defaults: defaults).load() == .default)
        for key in ["subscriptions.v2", "watchLater.v2", "watchHistory.v2", "skipSettings.v2"] {
            #expect(defaults.object(forKey: key) == nil)
        }
    }
}
