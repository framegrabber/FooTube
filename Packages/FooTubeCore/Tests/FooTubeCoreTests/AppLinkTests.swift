import FooTubeCore
import Foundation
import Testing

@Suite("footube:// links")
struct AppLinkTests {
    private let id = VideoID("dQw4w9WgXcQ")

    private func link(_ string: String) -> AppLink? {
        URL(string: string).flatMap(AppLink.init)
    }

    @Test(arguments: [
        "footube://play?v=dQw4w9WgXcQ",
        "FOOTUBE://PLAY?v=dQw4w9WgXcQ",
        "footube://play?v=https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s",
        "footube://play?v=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ%26t%3D42s",
        "footube://play?v=https://youtu.be/dQw4w9WgXcQ?si=abc",
        "footube://play?v=https://m.youtube.com/watch?feature=share&v=dQw4w9WgXcQ",
    ])
    func `play links accept IDs and YouTube URLs`(string: String) throws {
        let id = try #require(id)
        #expect(link(string) == .play(id))
    }

    @Test func `an unencoded URL whose v isn't first still yields its ID`() throws {
        // `feature=share&v=…` unencoded: the link's query splits into v=https://m.youtube.com/watch?feature=share
        // and v=dQw4w9WgXcQ; the first `v` has no video ID, the second has.
        let id = try #require(id)
        let url = try #require(URL(string: "footube://play?v=https://m.youtube.com/watch?feature=share&v=dQw4w9WgXcQ"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "v" }.compactMap(\.value)
        #expect(items == ["https://m.youtube.com/watch?feature=share", "dQw4w9WgXcQ"])
        #expect(AppLink(url) == .play(id))
    }

    @Test func `watch later links carry an optional trimmed title`() throws {
        let id = try #require(id)
        #expect(link("footube://watch-later?v=dQw4w9WgXcQ") == .watchLater(id, title: nil))
        #expect(link("footube://watch-later?v=https://youtu.be/dQw4w9WgXcQ&title=%20Never%20Gonna%20") == .watchLater(id, title: "Never Gonna"))
        #expect(link("footube://watch-later?title=&v=dQw4w9WgXcQ") == .watchLater(id, title: nil))
    }

    @Test func `watch later titles lose control and format characters and stop at 200 characters`() throws {
        let id = try #require(id)
        // U+202E right-to-left override, BEL, U+200B zero width space, a line break.
        #expect(link("footube://watch-later?v=dQw4w9WgXcQ&title=%E2%80%AEevil%07%E2%80%8B%0Atitle") == .watchLater(id, title: "evil title"))
        #expect(link("footube://watch-later?v=dQw4w9WgXcQ&title=\(String(repeating: "a", count: 300_000))") == .watchLater(id, title: String(repeating: "a", count: 200)))
        #expect(link("footube://watch-later?v=dQw4w9WgXcQ&title=%E2%80%AE%0A%00") == .watchLater(id, title: nil))
    }

    @Test(arguments: [
        "footube://play",
        "footube://play?v=",
        "footube://play?v=not-an-id",
        "footube://play?v=https://example.com/watch?v=dQw4w9WgXcQ",
        "footube://stop?v=dQw4w9WgXcQ",
        "footube:play?v=dQw4w9WgXcQ",
        "https://play?v=dQw4w9WgXcQ",
        "youtube://play?v=dQw4w9WgXcQ",
    ])
    func `rejects other links`(string: String) {
        #expect(link(string) == nil)
    }

    @Test func `a bare summary uses the ID as title and the standard thumbnail`() throws {
        let id = try #require(id)
        let bare = VideoSummary.bare(id, title: nil)
        #expect(bare.title == "dQw4w9WgXcQ")
        #expect(bare.thumbnail?.absoluteString == "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
        #expect(bare.channel == nil && bare.duration == nil)
        #expect(VideoSummary.bare(id, title: "A title").title == "A title")
    }

    @Test func `a bare summary cleans the title it is given; nothing left falls back to the ID`() throws {
        let id = try #require(id)
        #expect(VideoSummary.bare(id, title: "\u{202E}  Big Buck Bunny\u{0}  ").title == "Big Buck Bunny")
        #expect(VideoSummary.bare(id, title: String(repeating: "🐰", count: 300)).title == String(repeating: "🐰", count: 200))
        #expect(VideoSummary.bare(id, title: "\u{200E}\u{FEFF} ").title == "dQw4w9WgXcQ")
    }
}
