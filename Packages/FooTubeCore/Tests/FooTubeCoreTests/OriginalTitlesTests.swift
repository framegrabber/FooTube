@testable import FooTubeCore
import Foundation
import Testing

@Suite("Original titles")
struct OriginalTitlesTests {
    private let blender = VideoID("sO_lhW8av3U")!

    private func video(_ id: VideoID, title: String) -> VideoSummary {
        VideoSummary(id: id, title: title, channel: ChannelRef(id: "UCSMOQeBJ2RAnuFungnQOxLg", name: "Blender"), duration: "2:29", viewCount: nil, published: "vor 2 Wochen", thumbnail: nil)
    }

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func titles(_ server: StubURLProtocol.Server, file: URL? = nil) -> OriginalTitles {
        OriginalTitles(session: server.session, baseURL: server.baseURL, file: file, timeout: .seconds(2))
    }

    @Test func `the oEmbed title replaces the translated one and keeps the other fields`() async throws {
        let server = StubURLProtocol.Server([.response(status: 200, body: json(["title": "Blender Conference 2026 Recap", "author_name": "Blender"]))])
        let result = await titles(server).originals(for: [video(blender, title: "Blender Conference 2026 Rückblick")])
        #expect(result.map(\.title) == ["Blender Conference 2026 Recap"])
        #expect(result.first?.published == "vor 2 Wochen")
        #expect(result.first?.duration == "2:29")
        let request = try #require(server.requests.first)
        #expect(request.path == "/oembed")
        let query = URLComponents(string: "https://x/?" + (request.query ?? ""))?.queryItems ?? []
        #expect(query.first { $0.name == "url" }?.value == "https://www.youtube.com/watch?v=sO_lhW8av3U")
    }

    @Test func `a known title needs no request, also after a restart`() async {
        let file = FileManager.default.temporaryDirectory.appending(path: "original-titles-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let server = StubURLProtocol.Server([.response(status: 200, body: json(["title": "Recap"]))])
        _ = await titles(server, file: file).originals(for: [video(blender, title: "Rückblick")])
        let again = await titles(server, file: file).originals(for: [video(blender, title: "Rückblick"), video(blender, title: "Rückblick")])
        #expect(again.map(\.title) == ["Recap", "Recap"])
        #expect(server.requests.count == 1)
    }

    @Test func `embedding disabled falls back to the player's title`() async throws {
        let server = StubURLProtocol.Server([
            .response(status: 401),
            .response(status: 200, body: json(["playabilityStatus": ["status": "UNPLAYABLE"], "videoDetails": ["videoId": "sO_lhW8av3U", "title": "Recap"]])),
        ])
        let result = await titles(server).originals(for: [video(blender, title: "Rückblick")])
        #expect(result.map(\.title) == ["Recap"])
        let player = try #require(server.requests.last)
        #expect(player.method == "POST")
        #expect(player.path == "/youtubei/v1/player")
        let body = try #require(JSONSerialization.jsonObject(with: player.body) as? [String: Any])
        #expect(body["videoId"] as? String == "sO_lhW8av3U")
    }

    @Test func `a live video without an oEmbed title falls back to the player`() async {
        let server = StubURLProtocol.Server([
            .response(status: 200, body: json(["type": "video", "html": "<iframe title=\"Live\"></iframe>"])),
            .response(status: 200, body: json(["videoDetails": ["videoId": "sO_lhW8av3U", "title": "Live now"]])),
        ])
        let result = await titles(server).originals(for: [video(blender, title: "Jetzt live")])
        #expect(result.map(\.title) == ["Live now"])
    }

    @Test func `a player answer about another video is not taken`() async {
        let server = StubURLProtocol.Server([
            .response(status: 401),
            .response(status: 200, body: json(["videoDetails": ["videoId": "dQw4w9WgXcQ", "title": "Other"]])),
        ])
        let result = await titles(server).originals(for: [video(blender, title: "Rückblick")])
        #expect(result.map(\.title) == ["Rückblick"])
    }

    @Test func `a failed lookup keeps the list's title and is tried again`() async {
        let server = StubURLProtocol.Server([
            .failure(.timedOut),
            .response(status: 500),
            .response(status: 200, body: json(["title": "Recap"])),
        ])
        let lookup = titles(server)
        let first = await lookup.originals(for: [video(blender, title: "Rückblick")])
        #expect(first.map(\.title) == ["Rückblick"])
        let second = await lookup.originals(for: [video(blender, title: "Rückblick")])
        #expect(second.map(\.title) == ["Recap"])
        #expect(server.requests.count == 3)
    }

    @Test func `the order of the list is kept`() async {
        let ids = ["aaaaaaaaaaa", "bbbbbbbbbbb", "ccccccccccc"].map { VideoID($0)! }
        // Every lookup gets the same answer, whichever finishes first.
        let server = StubURLProtocol.Server(Array(repeating: .response(status: 200, body: json(["title": "Original"])), count: 3))
        let result = await titles(server).originals(for: ids.map { video($0, title: "Übersetzt") })
        #expect(result.map(\.id) == ids)
        #expect(result.allSatisfy { $0.title == "Original" })
    }
}
