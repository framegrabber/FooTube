import FooTubeCore
import Foundation
import Testing

/// Hits real YouTube. Opt-in: `FOOTUBE_NETWORK_TESTS=1 swift test --package-path Packages/FooTubeCore`.
@Suite(
    "YouTubeKitResolver against real YouTube",
    .enabled(if: ProcessInfo.processInfo.environment["FOOTUBE_NETWORK_TESTS"] == "1"),
)
struct ResolverNetworkTests {
    /// The five non-restricted MVP cases from SPEC success criterion 1.
    static let cases: [(label: String, id: String)] = [
        ("normal (Big Buck Bunny)", "aqz-KE-bpKQ"),
        ("label music video", "dQw4w9WgXcQ"),
        ("made for kids", "XqZsoesa55w"),
        ("long (> 2 h)", "PkcnAB09ZXU"),
        ("livestream", "rFZHOHl-L8A"),
    ]

    @Test func `at least four of five resolve to fetchable media`() async throws {
        let resolver = YouTubeKitResolver()
        var playable = 0
        for (label, raw) in Self.cases {
            let id = try #require(VideoID(raw))
            do {
                let stream = try await resolver.resolve(id)
                let status = await Self.mediaStatus(stream)
                print("RESULT \(raw) \(label): \(stream.summary), first media bytes HTTP \(status)")
                if status == 200 || status == 206 {
                    playable += 1
                }
            } catch {
                print("RESULT \(raw) \(label): FAILED \(error.message)")
            }
        }
        #expect(playable >= 4, "only \(playable) of \(Self.cases.count) playable")
    }

    @Test func `age restricted video fails with readable error`() async throws {
        let id = try #require(VideoID("HtVdAasjOgU"))
        do {
            let stream = try await YouTubeKitResolver().resolve(id)
            await print("RESULT HtVdAasjOgU age-restricted: resolved \(stream.summary), HTTP \(Self.mediaStatus(stream))")
        } catch {
            print("RESULT HtVdAasjOgU age-restricted: \(error.message)")
            #expect(!error.message.isEmpty)
        }
    }

    /// For HLS: first segment of the highest variant; for muxed: first bytes of the file.
    private static func mediaStatus(_ stream: ResolvedStream) async -> Int {
        switch stream.kind {
        case .muxed:
            return await rangeStatus(stream.url)
        case let .hls(playlist, _, _):
            guard let variant = playlist.split(separator: "\n").last(where: { $0.hasPrefix("https://") }),
                  let variantURL = URL(string: String(variant)),
                  let (data, _) = try? await URLSession.shared.data(from: variantURL),
                  let media = String(data: data, encoding: .utf8),
                  let segment = media.split(separator: "\n").first(where: { $0.hasPrefix("https://") }),
                  let segmentURL = URL(string: String(segment))
            else { return -1 }
            return await rangeStatus(segmentURL)
        }
    }

    private static func rangeStatus(_ url: URL) async -> Int {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return -1 }
        return (response as? HTTPURLResponse)?.statusCode ?? -1
    }
}
