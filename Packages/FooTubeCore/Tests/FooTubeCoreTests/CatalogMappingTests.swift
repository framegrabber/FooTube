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
}
