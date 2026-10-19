@testable import FooTubeCore
import Foundation
import InnerTubeKit
import Testing

@Suite("Video details")
struct VideoDetailsTests {
    private func video(_ id: String, duration: String? = "10:00", channel: String? = nil) throws -> VideoSummary {
        let id = try #require(VideoID(id))
        return VideoSummary(id: id, title: id.rawValue, channel: channel.map { ChannelRef(id: $0, name: nil) }, duration: duration, viewCount: nil, published: nil, thumbnail: nil)
    }

    @Test func `chapters are ordered by start, untitled or unstarted ones dropped, one per start`() {
        let raw: [MoreVideoInfosResponse.Chapter] = [
            .init(title: "Lighting", startTimeSeconds: 300),
            .init(title: "Intro", startTimeSeconds: 0),
            .init(title: "No start"),
            .init(title: "", startTimeSeconds: 120),
            .init(title: "Modeling", startTimeSeconds: 60),
            .init(title: "Modeling again", startTimeSeconds: 60),
        ]
        let chapters = InnerTubeCatalog.chapters(raw)
        #expect(chapters.map(\.title) == ["Intro", "Modeling", "Lighting"])
        #expect(chapters.map(\.start) == [0, 60, 300])
    }

    @Test func `up next skips the current, watched and live videos`() throws {
        let details = try VideoDetails(chapters: [], channelID: nil, related: [
            video("aaaaaaaaaaa"), // current
            video("bbbbbbbbbbb"), // watched
            video("ccccccccccc", duration: nil), // live
            video("ddddddddddd"),
            video("eeeeeeeeeee"),
        ])
        let current = try #require(VideoID("aaaaaaaaaaa"))
        let next = details.upNext(after: current) { $0.rawValue == "bbbbbbbbbbb" }
        #expect(next?.id.rawValue == "ddddddddddd")
    }

    @Test func `no up next when every related video is ruled out`() throws {
        let details = try VideoDetails(chapters: [], channelID: nil, related: [video("bbbbbbbbbbb"), video("ccccccccccc", duration: nil)])
        let current = try #require(VideoID("aaaaaaaaaaa"))
        #expect(details.upNext(after: current) { _ in true } == nil)
    }

    @Test func `up next prefers a fitting video from the same channel`() throws {
        let details = try VideoDetails(chapters: [], channelID: "UCsame", related: [
            video("bbbbbbbbbbb", channel: "UCother"),
            video("ccccccccccc", channel: "UCsame"), // watched
            video("ddddddddddd", channel: "UCsame"),
        ])
        let current = try #require(VideoID("aaaaaaaaaaa"))
        #expect(details.upNext(after: current) { $0.rawValue == "ccccccccccc" }?.id.rawValue == "ddddddddddd")
        #expect(details.upNext(after: current) { $0.rawValue != "bbbbbbbbbbb" }?.id.rawValue == "bbbbbbbbbbb", "falls back to another channel")
    }
}
