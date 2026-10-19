@testable import FooTubeCore
import Foundation
import InnerTubeKit
import Testing

@Suite("Catalog mapping from InnerTubeKit results")
struct CatalogMappingTests {
    private func thumb(_ width: Int) -> YTThumbnail {
        YTThumbnail(width: width, height: width * 9 / 16, url: URL(string: "https://i.ytimg.com/vi/x/\(width).jpg")!)
    }

    @Test func `maps a video with channel, duration and the smallest thumbnail at least 480 wide`() throws {
        let video = YTVideo(
            videoId: "dQw4w9WgXcQ",
            title: "Never Gonna Give You Up",
            channel: YTLittleChannelInfos(channelId: "UCuAXFkgsw1L7xaCfnd5JJOw", name: "Rick Astley"),
            viewCount: "1.6B views",
            timePosted: "16 years ago",
            timeLength: "3:33",
            thumbnails: [thumb(168), thumb(1280), thumb(720), thumb(336)],
        )
        let summary = try #require(InnerTubeCatalog.summary(video))
        #expect(summary.id.rawValue == "dQw4w9WgXcQ")
        #expect(summary.title == "Never Gonna Give You Up")
        #expect(summary.channel == ChannelRef(id: "UCuAXFkgsw1L7xaCfnd5JJOw", name: "Rick Astley"))
        #expect(summary.duration == "3:33")
        #expect(summary.thumbnail?.lastPathComponent == "720.jpg")
    }

    @Test func `falls back to the largest thumbnail when none is wide enough`() throws {
        let video = YTVideo(videoId: "dQw4w9WgXcQ", thumbnails: [thumb(168), thumb(336)])
        #expect(try #require(InnerTubeCatalog.summary(video)).thumbnail?.lastPathComponent == "336.jpg")
    }

    @Test func `drops results whose ID is not a valid video ID`() {
        #expect(InnerTubeCatalog.summary(YTVideo(videoId: "bad")) == nil)
    }

    @Test func `live and upcoming videos without a length have no duration`() throws {
        let video = YTVideo(videoId: "rFZHOHl-L8A", title: "lofi", timeLength: "")
        #expect(try #require(InnerTubeCatalog.summary(video)).duration == nil)
    }

    @Test func `appending a page skips videos already in the list and keeps order`() throws {
        let ids = ["aaaaaaaaaaa", "bbbbbbbbbbb", "ccccccccccc"]
        let summaries = try ids.map { try #require(InnerTubeCatalog.summary(YTVideo(videoId: $0))) }
        let merged = [summaries[0], summaries[1]].appendingUnique([summaries[1], summaries[2], summaries[2]])
        #expect(merged.map(\.id.rawValue) == ids)
    }

    @Test func `drops members-only videos, which don't play without a member login`() {
        #expect(InnerTubeCatalog.summary(YTVideo(videoId: "mv4G9VHL7KE", memberOnly: true)) == nil)
        #expect(InnerTubeCatalog.summary(YTVideo(videoId: "r1jOsar2zV4", memberOnly: false)) != nil)
    }

    private func fixture(_ name: String) throws -> JSON {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSON(data: Data(contentsOf: url))
    }

    /// Recorded from Alexandre Chappel's "Videos" tab (trimmed): uploads 2 and 4 are members-only.
    @Test func `channel uploads page leaves out members-only uploads`() throws {
        let response = try ChannelVideosResponse.decodeJSON(json: fixture("channel-videos-members-only"))
        #expect(response.videos.map(\.videoId) == ["r1jOsar2zV4", "mv4G9VHL7KE", "gPW_mitgosw", "JMZpyEE_rC0"])
        let channel = ChannelRef(id: "UCe1Aj6VEO299Yq4WkXdoD3Q", name: response.name)
        let page = InnerTubeCatalog.page(response.videos, token: response.continuation, visitorData: nil, channel: channel)
        #expect(page.items.map(\.id.rawValue) == ["r1jOsar2zV4", "gPW_mitgosw"])
        #expect(page.items.allSatisfy { $0.channel?.id == channel.id })
        #expect(page.next?.token == "next")
        #expect(page.channels.isEmpty)
    }

    @Test func `channel continuation page leaves out members-only uploads`() throws {
        let response = try ChannelVideosResponse.Continuation.decodeJSON(json: fixture("channel-videos-continuation-members-only"))
        #expect(response.videos.map(\.videoId) == ["-theQc6J5Jg", "496QJksdx3o", "mv4G9VHL7KE"])
        let page = InnerTubeCatalog.page(response.videos, token: response.continuation, visitorData: nil)
        #expect(page.items.map(\.id.rawValue) == ["-theQc6J5Jg", "496QJksdx3o"])
        #expect(page.next?.token == "next")
    }

    @Test func `maps a channel search result with handle, subscribers and avatar`() throws {
        let channel = YTChannel(
            name: "Alexandre Chappel",
            channelId: "UCe1Aj6VEO299Yq4WkXdoD3Q",
            handle: "@achappel",
            thumbnails: [thumb(88), thumb(176)],
            subscriberCount: "457K subscribers",
        )
        let summary = try #require(InnerTubeCatalog.channelSummary(channel))
        #expect(summary.id == "UCe1Aj6VEO299Yq4WkXdoD3Q")
        #expect(summary.name == "Alexandre Chappel")
        #expect(summary.handle == "@achappel")
        #expect(summary.subscriberCount == "457K subscribers")
        #expect(summary.avatar?.lastPathComponent == "176.jpg")
        #expect(summary.ref == ChannelRef(id: "UCe1Aj6VEO299Yq4WkXdoD3Q", name: "Alexandre Chappel"))
    }

    @Test func `a channel without a name shows its handle, one without either is dropped`() throws {
        let handleOnly = YTChannel(channelId: "UCe1Aj6VEO299Yq4WkXdoD3Q", handle: "@achappel")
        #expect(try #require(InnerTubeCatalog.channelSummary(handleOnly)).name == "@achappel")
        #expect(InnerTubeCatalog.channelSummary(YTChannel(channelId: "UCe1Aj6VEO299Yq4WkXdoD3Q")) == nil)
    }

    @Test func `search page separates videos and channels and lists each channel once`() {
        let chappel = YTChannel(name: "Alexandre Chappel", channelId: "UCe1Aj6VEO299Yq4WkXdoD3Q")
        let rick = YTChannel(name: "Rick Astley", channelId: "UCuAXFkgsw1L7xaCfnd5JJOw")
        let results: [any YTSearchResult] = [chappel, YTVideo(videoId: "dQw4w9WgXcQ"), rick, chappel]
        let page = InnerTubeCatalog.page(results, token: nil, visitorData: nil)
        #expect(page.items.map(\.id.rawValue) == ["dQw4w9WgXcQ"])
        #expect(page.channels.map(\.id) == ["UCe1Aj6VEO299Yq4WkXdoD3Q", "UCuAXFkgsw1L7xaCfnd5JJOw"])
        #expect(page.next == nil)
    }
}
