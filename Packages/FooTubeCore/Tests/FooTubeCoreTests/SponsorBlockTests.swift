@testable import FooTubeCore
import Foundation
import Testing

@Suite("SponsorBlock client")
struct SponsorBlockTests {
    let fixture: Data = {
        let url = Bundle.module.url(forResource: "skipsegments-prefix", withExtension: "json", subdirectory: "Fixtures")!
        return try! Data(contentsOf: url)
    }()

    @Test func `hash prefix is the first four hex characters of SHA-256 of the video ID`() throws {
        // printf %s dQw4w9WgXcQ | shasum -a 256 → 5f6b…
        #expect(try SponsorBlockClient.hashPrefix(for: #require(VideoID("dQw4w9WgXcQ"))) == "5f6b")
    }

    @Test func `request asks for all configured categories and skip actions only`() throws {
        let client = SponsorBlockClient()
        let url = try client.requestURL(for: #require(VideoID("dQw4w9WgXcQ")))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.path == "/api/skipSegments/5f6b")
        let categories = try #require(items.first { $0.name == "categories" }?.value)
        #expect(try Set(JSONDecoder().decode([String].self, from: Data(categories.utf8))) == Set(SponsorCategory.allCases.map(\.rawValue)))
        #expect(items.first { $0.name == "actionType" }?.value == "skip")
    }

    @Test func `keeps only skip segments of the requested video in known categories, sorted by start`() throws {
        let segments = try SponsorBlockClient.decode(fixture, for: #require(VideoID("zergV5YUDjk")))
        #expect(segments.map(\.id) == ["intro-1", "sponsor-1", "selfpromo-1"])
        #expect(segments[1] == SkipSegment(id: "sponsor-1", category: .sponsor, start: 51.179, end: 102.219))
    }

    @Test func `returns no segments for a video missing from the response`() throws {
        #expect(try SponsorBlockClient.decode(fixture, for: #require(VideoID("dQw4w9WgXcQ"))).isEmpty)
    }

    @Test func `malformed response yields no segments instead of an error`() throws {
        #expect(try SponsorBlockClient.decode(Data("<html>".utf8), for: #require(VideoID("dQw4w9WgXcQ"))).isEmpty)
    }

    @Test func `only sponsor is auto-skipped`() {
        #expect(SponsorCategory.allCases.filter(\.autoSkips) == [.sponsor])
    }
}
