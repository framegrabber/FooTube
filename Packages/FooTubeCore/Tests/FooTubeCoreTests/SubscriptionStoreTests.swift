import FooTubeCore
import Foundation
import SwiftData
import Testing

@MainActor
@Suite("Local subscriptions")
struct SubscriptionStoreTests {
    let blender = ChannelRef(id: "UCSMOQeBJ2RAnuFungnQOxLg", name: "Blender")
    let rick = ChannelRef(id: "UCuAXFkgsw1L7xaCfnd5JJOw", name: "Rick Astley")

    @Test func `subscribing twice keeps one entry and unsubscribing removes it`() throws {
        let store = try SubscriptionStore(inMemory: true)
        try store.subscribe(blender, avatar: nil)
        try store.subscribe(blender, avatar: URL(string: "https://yt3.ggpht.com/a.jpg"))
        #expect(try store.channels().map(\.id) == [blender.id])
        #expect(try store.isSubscribed(blender.id))
        try store.unsubscribe(blender.id)
        #expect(try store.channels().isEmpty)
        #expect(try !store.isSubscribed(blender.id))
    }

    @Test func `channels are listed alphabetically by name`() throws {
        let store = try SubscriptionStore(inMemory: true)
        try store.subscribe(rick, avatar: nil)
        try store.subscribe(blender, avatar: nil)
        #expect(try store.channels().map(\.name) == ["Blender", "Rick Astley"])
    }

    @Test func `subscriptions survive reopening the store`() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "subs-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let store = try SubscriptionStore(url: url)
            try store.subscribe(blender, avatar: URL(string: "https://yt3.ggpht.com/a.jpg"))
        }
        let reopened = try SubscriptionStore(url: url)
        let channels = try reopened.channels()
        #expect(channels.map(\.id) == [blender.id])
        #expect(channels.first?.avatar?.absoluteString == "https://yt3.ggpht.com/a.jpg")
    }
}
