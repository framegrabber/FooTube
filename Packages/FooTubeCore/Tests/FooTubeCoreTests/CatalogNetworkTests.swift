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
}
