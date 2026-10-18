import FooTubeCore
import Foundation
import Testing

/// Hits real YouTube. Opt-in like ResolverNetworkTests.
@Suite(
    "InnerTubeCatalog against real YouTube",
    .enabled(if: ProcessInfo.processInfo.environment["FOOTUBE_NETWORK_TESTS"] == "1"),
)
struct CatalogNetworkTests {
    @Test func `search returns videos with thumbnails and a second page`() async throws {
        let catalog = InnerTubeCatalog()
        let first = try await catalog.search("blender open movie")
        print("RESULT search page 1: \(first.items.count) videos, e.g. \(first.items.prefix(3).map(\.title))")
        #expect(first.items.count >= 5)
        #expect(first.items.allSatisfy { $0.thumbnail != nil && !$0.title.isEmpty })
        let cursor = try #require(first.next)
        let second = try await catalog.moreSearchResults(cursor)
        print("RESULT search page 2: \(second.items.count) videos")
        #expect(!second.items.isEmpty)
        // YouTube repeats a few results across pages; lists dedupe with `VideoSummary.appendingUnique`.
        let new = second.items.filter { item in !first.items.contains { $0.id == item.id } }
        #expect(new.count >= second.items.count / 2)
    }

    @Test func `channel page lists uploads with channel info on every page`() async throws {
        let catalog = InnerTubeCatalog()
        let blender = "UCSMOQeBJ2RAnuFungnQOxLg" // Blender
        let page = try await catalog.channel(blender)
        print("RESULT channel \(page.channel.name ?? "?"): \(page.videos.items.count) videos, subs \(page.subscriberCount ?? "?"), avatar \(page.avatar != nil)")
        #expect(page.channel.name?.isEmpty == false)
        #expect(page.videos.items.count >= 10)
        #expect(page.videos.items.allSatisfy { $0.channel?.id == blender })
        let more = try await catalog.moreChannelVideos(#require(page.videos.next))
        print("RESULT channel page 2: \(more.items.count) videos")
        #expect(!more.items.isEmpty)
        #expect(more.items.allSatisfy { $0.channel?.id == blender })
    }
}
