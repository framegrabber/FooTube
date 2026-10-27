@testable import FooTubeCore
import Foundation
import Testing

/// Folding the browser inbox into Watch Later during its sync round (SPEC-browser-inbox → Client),
/// with two devices against the fake Worker.
@MainActor
@Suite("Browser inbox folding")
struct SyncInboxTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let bunny = "aqz-KE-bpKQ"
    let fright = "aiDHXKRxLeQ"

    private func remote(_ worker: FakeWorker) async throws -> WatchLaterDocument {
        let data = try #require(await worker.data(.watchLater))
        return try SyncCoding.decode(WatchLaterDocument.self, from: data)
    }

    @Test func `a new item becomes the newest Watch Later entry, is pushed and then deleted from the inbox`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        try living.watchLater.add(VideoSummary(id: #require(VideoID(fright)), title: "Sprite Fright", channel: nil, duration: nil, viewCount: nil, published: nil, thumbnail: nil))
        clock.advance(by: 60)
        await worker.addToInbox(bunny, title: "Big Buck Bunny", at: start + 30)
        clock.advance(by: 60)

        #expect(await living.engine.sync(.watchLater) == .synced(start + 120))
        let items = living.watchLater.items()
        #expect(items.map(\.id.rawValue) == [bunny, fright])
        #expect(items.first?.title == "Big Buck Bunny")
        #expect(items.first?.thumbnail?.absoluteString == "https://i.ytimg.com/vi/\(bunny)/hqdefault.jpg")
        #expect(try await remote(worker).entries.map(\.video.id.rawValue) == [bunny, fright])
        #expect(await worker.inboxCount == 0)
        #expect(living.takeChanges() == [.watchLater])
        let requests = await worker.requests
        #expect(try #require(requests.firstIndex(of: "DELETE inbox")) > #require(requests.lastIndex(of: "PUT watchLater")))
    }

    @Test func `an item without a title shows its video ID`() async {
        let worker = FakeWorker()
        let living = Device(worker, clock: TestClock(start + 10))
        await worker.addToInbox(bunny, title: nil, at: start)
        await living.engine.sync(.watchLater)
        #expect(living.watchLater.items().map(\.title) == [bunny])
    }

    @Test func `an item already in Watch Later is not added again`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        let video = try VideoSummary(id: #require(VideoID(bunny)), title: "Known title", channel: nil, duration: "9:57", viewCount: nil, published: nil, thumbnail: nil)
        try living.watchLater.add(video)
        await living.engine.sync(.watchLater)
        _ = living.takeChanges()
        clock.advance(by: 60)
        await worker.addToInbox(bunny, title: "Big Buck Bunny", at: start + 30)

        await living.engine.sync(.watchLater)
        #expect(living.watchLater.items() == [video])
        #expect(living.takeChanges().isEmpty)
        #expect(await worker.inboxCount == 0)
    }

    @Test func `an item removed before it was bookmarked comes back; one removed after stays removed`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        for id in [bunny, fright] {
            try living.watchLater.add(VideoSummary(id: #require(VideoID(id)), title: id, channel: nil, duration: nil, viewCount: nil, published: nil, thumbnail: nil))
        }
        clock.advance(by: 10)
        try living.watchLater.remove(#require(VideoID(bunny)))
        await worker.addToInbox(bunny, title: "Big Buck Bunny", at: start + 20) // after the removal
        await worker.addToInbox(fright, title: "Sprite Fright", at: start + 5)
        clock.advance(by: 10)
        try living.watchLater.remove(#require(VideoID(fright))) // after its bookmark
        clock.advance(by: 10)

        await living.engine.sync(.watchLater)
        #expect(living.watchLater.items().map(\.id.rawValue) == [bunny])
        #expect(try await remote(worker).entries.first { $0.video.id.rawValue == fright }?.removedAt == start + 20)
    }

    @Test func `two devices folding the same items end with one entry per video`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        let bedroom = Device(worker, clock: clock)
        await worker.addToInbox(bunny, title: "Big Buck Bunny", at: start)
        await worker.addToInbox(fright, title: "Sprite Fright", at: start + 1)
        clock.advance(by: 60)

        // The bedroom TV fetches the inbox before the living room deletes it.
        await worker.holdPuts()
        let livingRound = Task { await living.engine.sync(.watchLater) }
        while await worker.heldPutCount == 0 {
            await Task.yield()
        }
        await worker.releasePuts()
        let bedroomRound = Task { await bedroom.engine.sync(.watchLater) }
        _ = await (livingRound.value, bedroomRound.value)
        clock.advance(by: 10)
        await living.engine.sync(.watchLater)
        await bedroom.engine.sync(.watchLater)

        for device in [living, bedroom] {
            #expect(device.watchLater.items().map(\.id.rawValue) == [fright, bunny])
        }
        #expect(try await remote(worker).entries.count == 2)
        #expect(await worker.inboxCount == 0)
    }

    @Test func `a failed delete folds the items again next time without duplicates`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        await worker.addToInbox(bunny, title: "Big Buck Bunny", at: start)
        await worker.failClearingInbox(with: .offline(detail: "lost"))
        clock.advance(by: 60)

        #expect(await living.engine.sync(.watchLater) == .failed(.offline(detail: "lost")))
        #expect(living.watchLater.items().map(\.id.rawValue) == [bunny])
        #expect(try await remote(worker).entries.count == 1)
        #expect(await worker.inboxCount == 1)

        await worker.failClearingInbox(with: nil)
        clock.advance(by: 60)
        #expect(await living.engine.sync(.watchLater) == .synced(start + 120))
        #expect(living.watchLater.items().map(\.id.rawValue) == [bunny])
        #expect(try await remote(worker).entries.count == 1)
        #expect(await worker.inboxCount == 0)
    }

    @Test func `a Worker without an inbox is not a failure`() async throws {
        let worker = FakeWorker()
        let living = Device(worker, clock: TestClock(start))
        try living.watchLater.add(VideoSummary(id: #require(VideoID(bunny)), title: "B", channel: nil, duration: nil, viewCount: nil, published: nil, thumbnail: nil))
        #expect(await living.engine.sync(.watchLater) == .synced(start))
        #expect(await !worker.requests.contains("DELETE inbox"))
    }

    @Test func `an item folded long after it was bookmarked survives the next merge`() async throws {
        // With changedAt = the item's addedAt, the entry would count as pruned elsewhere (changed
        // before lastSyncAt, missing on the Worker) and be dropped by the push round.
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        await worker.enableInbox()
        await living.engine.sync(.watchLater)
        await worker.addToInbox(bunny, title: "Big Buck Bunny", at: start + 1)
        clock.advance(by: 3600)
        await living.engine.sync(.watchLater)
        clock.advance(by: 60)
        await living.engine.sync(.watchLater)
        #expect(living.watchLater.items().map(\.id.rawValue) == [bunny])
        #expect(try await remote(worker).entries.map(\.addedAt) == [start + 1])
    }

    @Test func `invalid video IDs are skipped`() {
        let items = [InboxItem(seq: 1, videoID: "not an id", title: nil, addedAt: start), InboxItem(seq: 2, videoID: bunny, title: nil, addedAt: start)]
        let folded = SyncInbox.fold(items, into: .empty, now: start + 1)
        #expect(folded.entries.map(\.video.id.rawValue) == [bunny])
        #expect(folded.entries.map(\.changedAt) == [start + 1])
    }
}
