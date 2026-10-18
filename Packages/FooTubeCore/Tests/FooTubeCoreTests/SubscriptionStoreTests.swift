import FooTubeCore
import Foundation
import Testing

@Suite("Local subscriptions")
struct SubscriptionStoreTests {
    let blender = ChannelRef(id: "UCSMOQeBJ2RAnuFungnQOxLg", name: "Blender")
    let rick = ChannelRef(id: "UCuAXFkgsw1L7xaCfnd5JJOw", name: "Rick Astley")

    private func freshDefaults() -> UserDefaults {
        let suite = "footube-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func `subscribing twice keeps one entry and unsubscribing removes it`() throws {
        let store = SubscriptionStore(defaults: freshDefaults())
        try store.subscribe(blender, avatar: nil)
        try store.subscribe(blender, avatar: URL(string: "https://yt3.ggpht.com/a.jpg"))
        #expect(store.channels().map(\.id) == [blender.id])
        #expect(store.channels().first?.avatar != nil)
        #expect(store.isSubscribed(blender.id))
        try store.unsubscribe(blender.id)
        #expect(store.channels().isEmpty)
        #expect(!store.isSubscribed(blender.id))
    }

    @Test func `re-subscribing without an avatar keeps the stored one`() throws {
        let store = SubscriptionStore(defaults: freshDefaults())
        try store.subscribe(blender, avatar: URL(string: "https://yt3.ggpht.com/a.jpg"))
        try store.subscribe(ChannelRef(id: blender.id, name: nil), avatar: nil)
        #expect(store.channels() == [Subscription(id: blender.id, name: "Blender", avatar: URL(string: "https://yt3.ggpht.com/a.jpg"))])
    }

    @Test func `channels are listed alphabetically by name`() throws {
        let store = SubscriptionStore(defaults: freshDefaults())
        try store.subscribe(rick, avatar: nil)
        try store.subscribe(blender, avatar: nil)
        #expect(store.channels().map(\.name) == ["Blender", "Rick Astley"])
    }

    @Test func `subscriptions survive a new store instance on the same defaults`() throws {
        let defaults = freshDefaults()
        try SubscriptionStore(defaults: defaults).subscribe(blender, avatar: URL(string: "https://yt3.ggpht.com/a.jpg"))
        let channels = SubscriptionStore(defaults: defaults).channels()
        #expect(channels.map(\.id) == [blender.id])
        #expect(channels.first?.avatar?.absoluteString == "https://yt3.ggpht.com/a.jpg")
    }
}
