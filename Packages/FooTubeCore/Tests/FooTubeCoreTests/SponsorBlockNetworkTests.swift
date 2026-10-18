import FooTubeCore
import Foundation
import Testing

/// Hits the public SponsorBlock API. Opt-in like ResolverNetworkTests.
@Suite(
    "SponsorBlock against the public API",
    .enabled(if: ProcessInfo.processInfo.environment["FOOTUBE_NETWORK_TESTS"] == "1"),
)
struct SponsorBlockNetworkTests {
    @Test func `known sponsored video returns a sponsor segment`() async throws {
        let segments = try await SponsorBlockClient().segments(for: #require(VideoID("zergV5YUDjk")))
        print("RESULT zergV5YUDjk: \(segments.map { "\($0.category.rawValue) \($0.start)-\($0.end)" })")
        #expect(segments.contains { $0.category == .sponsor })
    }

    @Test func `unreachable server yields no segments quickly`() async throws {
        let client = try SponsorBlockClient(baseURL: #require(URL(string: "https://127.0.0.1:9")), timeout: .seconds(2))
        let started = ContinuousClock.now
        let segments = try await client.segments(for: #require(VideoID("zergV5YUDjk")))
        #expect(segments.isEmpty)
        #expect(ContinuousClock.now - started < .seconds(5))
    }
}
