@testable import FooTubeCore
import Foundation
import InnerTubeKit
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
        print("RESULT channel \(page.channel.name ?? "?"): \(page.videos.items.count) videos, subs \(page.subscriberCount ?? "?"), handle \(page.handle ?? "?"), count \(page.videoCount ?? "?"), description \(page.description?.prefix(60) ?? "?"), avatar \(page.avatar != nil)")
        #expect(page.channel.name?.isEmpty == false)
        #expect(page.handle?.hasPrefix("@") == true)
        #expect(page.videoCount != nil)
        #expect(page.description != nil)
        #expect(page.videos.items.count >= 10)
        #expect(page.videos.items.allSatisfy { $0.channel?.id == blender })
        let more = try await catalog.moreChannelVideos(#require(page.videos.next))
        print("RESULT channel page 2: \(more.items.count) videos")
        #expect(!more.items.isEmpty)
        #expect(more.items.allSatisfy { $0.channel?.id == blender })
    }

    @Test func `channel page leaves out members-only uploads`() async throws {
        let chappel = "UCe1Aj6VEO299Yq4WkXdoD3Q" // Alexandre Chappel, posts members-only videos regularly
        let model = YouTubeModel()
        let header = try await ChannelInfosResponse.sendThrowingRequest(youtubeModel: model, data: [.browseId: chappel])
        let params = try #require(header.requestParams[.videos])
        let raw = try await ChannelVideosResponse.sendThrowingRequest(youtubeModel: model, data: [.browseId: chappel, .params: params])
        let membersOnly = Set(raw.videos.filter { $0.memberOnly == true }.map(\.videoId))
        print("RESULT members-only uploads on page 1: \(membersOnly.sorted()) of \(raw.videos.count)")
        #expect(!membersOnly.isEmpty, "badge not detected; did YouTube change the lockup?")

        let page = try await InnerTubeCatalog().channel(chappel)
        #expect(!page.videos.items.isEmpty)
        #expect(page.videos.items.allSatisfy { !membersOnly.contains($0.id.rawValue) })
    }

    @Test func `search lists the matching channel`() async throws {
        let page = try await InnerTubeCatalog().search("Alexandre Chappel")
        print("RESULT search channels: \(page.channels.map { "\($0.name) \($0.subscriberCount ?? "?")" })")
        let channel = try #require(page.channels.first { $0.id == "UCe1Aj6VEO299Yq4WkXdoD3Q" })
        #expect(channel.name == "Alexandre Chappel")
        #expect(channel.avatar != nil)
        #expect(!page.items.isEmpty)
    }

    @Test func `feed merges two channels newest first with English relative ages`() async throws {
        let channels = [ChannelRef(id: "UCSMOQeBJ2RAnuFungnQOxLg", name: "Blender"), ChannelRef(id: "UCuAXFkgsw1L7xaCfnd5JJOw", name: "Rick Astley")]
        let snapshot = try #require(await FeedService(catalog: InnerTubeCatalog()).refresh(channels))
        print("RESULT feed: \(snapshot.items.count) items, first: \(snapshot.items.prefix(3).map { "\($0.channel?.name ?? "?"): \($0.published ?? "?")" })")
        #expect(Set(snapshot.items.compactMap(\.channel?.id)) == Set(channels.map(\.id)))
        let parsed = snapshot.items.prefix(10).compactMap { $0.published.flatMap(FeedMerger.age(of:)) }
        #expect(parsed.count >= 8, "ages not parseable: \(snapshot.items.prefix(10).map(\.published))")
        #expect(parsed == parsed.sorted())
    }

    @Test func `watch page lists chapters and related videos`() async throws {
        // Blender Guru "Beginner Blender 4.0 Tutorial", ~95 chapters in its description.
        let details = try await InnerTubeCatalog().details(#require(VideoID("4haAdmHqGOw")))
        print("RESULT details: \(details.chapters.count) chapters \(details.chapters.prefix(3).map { "\($0.start) \($0.title)" }), \(details.related.count) related, e.g. \(details.related.prefix(3).map(\.title))")
        #expect(details.chapters.count >= 3)
        #expect(details.chapters.first?.start == 0)
        #expect(details.related.count >= 5)
        #expect(details.related.allSatisfy { !$0.title.isEmpty && $0.thumbnail != nil })
    }

    @Test func `suggestions complete a partial query`() async throws {
        let suggestions = try await InnerTubeCatalog().suggestions("blender tut")
        print("RESULT suggestions: \(suggestions)")
        #expect(suggestions.count >= 3)
        #expect(suggestions.allSatisfy { $0.localizedCaseInsensitiveContains("blender") })
    }

    @Test func `original titles come back in the video's own language`() async throws {
        let ids = ["WhWc3b3KhnY", "ub-oC-r7JQM", "fudtEN1O70Q"] // English, Japanese, German with embedding disabled
        let placeholders = try ids.map { try VideoSummary(id: #require(VideoID($0)), title: "?", channel: nil, duration: nil, viewCount: nil, published: nil, thumbnail: nil) }
        let titles = await OriginalTitles(file: nil).originals(for: placeholders).map(\.title)
        print("RESULT original titles: \(titles)")
        #expect(titles[0] == "Spring - Blender Open Movie")
        #expect(titles[1].contains("iPhone水没"))
        #expect(titles[2] != "?") // oEmbed 401, title from the player
    }
}
