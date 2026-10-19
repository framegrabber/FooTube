@testable import FooTubeCore
import Foundation
import Testing

/// Catalog double: per-channel uploads, optional failures and delays; records peak concurrency.
private actor FakeChannels: Catalog {
    let uploads: [String: [VideoSummary]]
    let failing: Set<String>
    let delays: [String: Duration]
    private(set) var running = 0
    private(set) var peak = 0

    init(uploads: [String: [VideoSummary]], failing: Set<String> = [], delays: [String: Duration] = [:]) {
        self.uploads = uploads
        self.failing = failing
        self.delays = delays
    }

    func channel(_ id: String) async throws(CatalogError) -> ChannelPage {
        running += 1
        peak = max(peak, running)
        try? await Task.sleep(for: delays[id] ?? .milliseconds(20))
        running -= 1
        if failing.contains(id) {
            throw .requestFailed("offline")
        }
        return ChannelPage(channel: ChannelRef(id: id, name: id), avatar: nil, subscriberCount: nil, videos: ResultsPage(items: uploads[id] ?? [], next: nil))
    }

    func search(_: String) async throws(CatalogError) -> ResultsPage {
        throw .requestFailed("unused")
    }

    func moreSearchResults(_: PageCursor) async throws(CatalogError) -> ResultsPage {
        throw .requestFailed("unused")
    }

    func moreChannelVideos(_: PageCursor) async throws(CatalogError) -> ResultsPage {
        throw .requestFailed("unused")
    }

    func details(_: VideoID) async throws(CatalogError) -> VideoDetails {
        throw .requestFailed("unused")
    }

    func suggestions(_: String) async throws(CatalogError) -> [String] {
        throw .requestFailed("unused")
    }
}

@Suite("Feed refresh")
struct FeedServiceTests {
    private func video(_ id: String, channel: String, _ published: String) -> VideoSummary {
        VideoSummary(id: VideoID(id)!, title: id, channel: ChannelRef(id: channel, name: channel), duration: nil, viewCount: nil, published: published, thumbnail: nil)
    }

    private func refs(_ ids: String...) -> [ChannelRef] {
        ids.map { ChannelRef(id: $0, name: $0) }
    }

    @Test func `a failing channel keeps its videos from the previous feed`() async throws {
        let previous = FeedSnapshot(fetchedAt: .distantPast, items: [video("bbbbbbbbbbb", channel: "B", "1 day ago")])
        let catalog = FakeChannels(uploads: ["A": [video("aaaaaaaaaaa", channel: "A", "2 hours ago")]], failing: ["B"])
        let snapshot = try #require(await FeedService(catalog: catalog).refresh(refs("A", "B"), previous: previous))
        #expect(snapshot.items.map(\.id.rawValue) == ["aaaaaaaaaaa", "bbbbbbbbbbb"])
    }

    @Test func `all channels failing yields no snapshot`() async {
        let catalog = FakeChannels(uploads: [:], failing: ["A", "B"])
        #expect(await FeedService(catalog: catalog).refresh(refs("A", "B")) == nil)
    }

    @Test func `no subscriptions yields an empty snapshot`() async throws {
        let snapshot = try #require(await FeedService(catalog: FakeChannels(uploads: [:])).refresh([]))
        #expect(snapshot.items.isEmpty)
    }

    @Test func `at most four channels are fetched at once`() async {
        let ids = (0 ..< 10).map { "C\($0)" }
        let catalog = FakeChannels(uploads: [:])
        _ = await FeedService(catalog: catalog).refresh(ids.map { ChannelRef(id: $0, name: $0) })
        #expect(await catalog.peak == FeedService.maxConcurrentChannels)
    }

    @Test func `equal ages follow channel order, not completion order`() async throws {
        // A finishes last, but is listed first.
        let catalog = FakeChannels(
            uploads: ["A": [video("aaaaaaaaaaa", channel: "A", "1 day ago")], "B": [video("bbbbbbbbbbb", channel: "B", "1 day ago")]],
            delays: ["A": .milliseconds(200), "B": .milliseconds(1)],
        )
        let snapshot = try #require(await FeedService(catalog: catalog).refresh(refs("A", "B")))
        #expect(snapshot.items.map(\.id.rawValue) == ["aaaaaaaaaaa", "bbbbbbbbbbb"])
    }
}
