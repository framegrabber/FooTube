@testable import FooTubeCore
import Foundation
import Testing

/// An in-memory Worker implementing the Contract: ETags per version, `If-Match`/`If-None-Match: *`,
/// `412` with the current document and ETag (none when the store doesn't exist); the browser inbox
/// once `enableInbox()` was called (before that it answers like a Worker without `INBOX_TOKEN`).
actor FakeWorker: SyncTransport {
    private var stores: [SyncStoreName: (data: Data, version: Int)] = [:]
    private var version = 0
    private(set) var requests: [String] = []
    private var failure: SyncError?
    /// Written by "another device" right before the next `PUT` of the store arrives.
    private var foreignWrites: [SyncStoreName: [Data]] = [:]
    private var holdingPuts = false
    private var heldPuts: [CheckedContinuation<Void, Never>] = []
    private var inboxItems: [InboxItem]?
    private var inboxSeq = 0
    private var clearFailure: SyncError?
    /// ETags as Cloudflare's edge sends them on compressed responses (`W/"n"`).
    private var weakETags = false
    private(set) var preconditions: [SyncClient.Precondition] = []

    func inbox() async throws(SyncError) -> [InboxItem]? {
        requests.append("GET inbox")
        if let failure {
            throw failure
        }
        return inboxItems
    }

    func clearInbox(through seq: Int) async throws(SyncError) {
        requests.append("DELETE inbox")
        if let error = failure ?? clearFailure {
            throw error
        }
        inboxItems?.removeAll { $0.seq <= seq }
    }

    func enableInbox() {
        inboxItems = inboxItems ?? []
    }

    /// `POST /v1/inbox`: a repeat of a video only updates its title.
    func addToInbox(_ videoID: String, title: String?, at date: Date) {
        enableInbox()
        if let index = inboxItems?.firstIndex(where: { $0.videoID == videoID }) {
            let item = inboxItems![index]
            inboxItems![index] = InboxItem(seq: item.seq, videoID: videoID, title: title ?? item.title, addedAt: item.addedAt)
            return
        }
        inboxSeq += 1
        inboxItems?.append(InboxItem(seq: inboxSeq, videoID: videoID, title: title, addedAt: date))
    }

    var inboxCount: Int? {
        inboxItems?.count
    }

    func failClearingInbox(with error: SyncError?) {
        clearFailure = error
    }

    func fetch(_ store: SyncStoreName) async throws(SyncError) -> (data: Data, etag: String)? {
        requests.append("GET \(store.rawValue)")
        if let failure {
            throw failure
        }
        return stores[store].map { ($0.data, etag($0.version)) }
    }

    func put(_ store: SyncStoreName, data: Data, precondition: SyncClient.Precondition) async throws(SyncError) -> SyncClient.PutResult {
        requests.append("PUT \(store.rawValue)")
        preconditions.append(precondition)
        if holdingPuts {
            await withCheckedContinuation { heldPuts.append($0) }
        }
        if let failure {
            throw failure
        }
        if let foreign = foreignWrites[store]?.first {
            foreignWrites[store]?.removeFirst()
            write(foreign, to: store)
        }
        let current = stores[store]
        let holds = switch precondition {
        case .create: current == nil
        case let .replace(sent): current.map { etag($0.version) == sent } ?? false
        }
        guard holds else { return .conflict(data: current?.data, etag: current.map { etag($0.version) }) }
        write(data, to: store)
        return .stored(etag(version))
    }

    func data(_ store: SyncStoreName) -> Data? {
        stores[store]?.data
    }

    func write(_ data: Data, to store: SyncStoreName) {
        version += 1
        stores[store] = (data, version)
    }

    func fail(with error: SyncError?) {
        failure = error
    }

    func writeBeforeNextPut(_ data: Data, to store: SyncStoreName) {
        foreignWrites[store, default: []].append(data)
    }

    func holdPuts() {
        holdingPuts = true
    }

    func releasePuts() {
        holdingPuts = false
        heldPuts.forEach { $0.resume() }
        heldPuts = []
    }

    var heldPutCount: Int {
        heldPuts.count
    }

    func useWeakETags() {
        weakETags = true
    }

    private func etag(_ version: Int) -> String {
        weakETags ? "W/\"\(version)\"" : "\"\(version)\""
    }
}

/// One Apple TV: its own `UserDefaults`, stores and engine, on the test's shared clock.
@MainActor
final class Device {
    let defaults: UserDefaults
    let subscriptions: SubscriptionStore
    let watchLater: WatchLaterStore
    let history: WatchHistory
    let settings: SkipSettingsStore
    private(set) var engine: SyncEngine
    private let changes = ChangeLog()

    @MainActor
    final class ChangeLog {
        var stores: [SyncStoreName] = []
    }

    init(_ worker: FakeWorker, clock: TestClock) {
        let suite = "footube-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        subscriptions = SubscriptionStore(defaults: defaults, now: clock.now)
        watchLater = WatchLaterStore(defaults: defaults, now: clock.now)
        history = WatchHistory(defaults: defaults, now: clock.now)
        settings = SkipSettingsStore(defaults: defaults, now: clock.now)
        engine = Self.engine(worker, clock: clock, defaults: defaults, changes: changes)
    }

    /// Stores whose local document a merge changed, in order; cleared on reading.
    func takeChanges() -> [SyncStoreName] {
        defer { changes.stores = [] }
        return changes.stores
    }

    /// A new engine on the same data, like the next launch.
    func relaunch(_ worker: FakeWorker, clock: TestClock) {
        engine = Self.engine(worker, clock: clock, defaults: defaults, changes: changes)
    }

    private static func engine(_ worker: FakeWorker, clock: TestClock, defaults: UserDefaults, changes: ChangeLog) -> SyncEngine {
        SyncEngine(
            transport: worker,
            subscriptions: SubscriptionStore(defaults: defaults, now: clock.now),
            watchLater: WatchLaterStore(defaults: defaults, now: clock.now),
            history: WatchHistory(defaults: defaults, now: clock.now),
            skipSettings: SkipSettingsStore(defaults: defaults, now: clock.now),
            defaults: defaults,
            now: clock.now,
            onLocalChange: { changes.stores.append($0) },
        )
    }
}

@MainActor
@Suite("Sync engine with two devices")
struct SyncEngineTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 24 * 60 * 60
    let blender = ChannelRef(id: "UCSMOQeBJ2RAnuFungnQOxLg", name: "Blender")
    let rick = ChannelRef(id: "UCuAXFkgsw1L7xaCfnd5JJOw", name: "Rick Astley")
    let kurz = ChannelRef(id: "UCsXVk37bltHxD1rDPwtNM8Q", name: "Kurzgesagt")
    let first = VideoID("r1jOsar2zV4")!
    let second = VideoID("aiDHXKRxLeQ")!

    private func summary(_ id: VideoID) -> VideoSummary {
        VideoSummary(id: id, title: id.rawValue, channel: nil, duration: nil, viewCount: nil, published: nil, thumbnail: nil)
    }

    private func remote<Document: SyncDocument>(_: Document.Type, _ worker: FakeWorker) async throws -> Document {
        let data = try #require(await worker.data(Document.store))
        return try SyncCoding.decode(Document.self, from: data)
    }

    @Test func `subscribe, unsubscribe and re-subscribe reach the other device`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        let bedroom = Device(worker, clock: clock)

        try living.subscriptions.subscribe(blender, avatar: nil)
        #expect(await living.engine.sync(.subscriptions) == .synced(start))
        clock.advance(by: 10)
        #expect(await bedroom.engine.sync(.subscriptions) == .synced(start + 10))
        #expect(bedroom.subscriptions.channels().map(\.id) == [blender.id])
        #expect(bedroom.takeChanges() == [.subscriptions])

        clock.advance(by: 10)
        try bedroom.subscriptions.unsubscribe(blender.id)
        await bedroom.engine.sync(.subscriptions)
        clock.advance(by: 10)
        await living.engine.sync(.subscriptions)
        #expect(!living.subscriptions.isSubscribed(blender.id))
        #expect(living.takeChanges() == [.subscriptions])

        clock.advance(by: 10)
        try living.subscriptions.subscribe(blender, avatar: nil)
        await living.engine.sync(.subscriptions)
        clock.advance(by: 10)
        await bedroom.engine.sync(.subscriptions)
        #expect(bedroom.subscriptions.isSubscribed(blender.id))
        #expect(try await remote(SubscriptionsDocument.self, worker).entries.map(\.removedAt) == [nil])
    }

    @Test func `edits made on both devices before syncing are both kept`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        let bedroom = Device(worker, clock: clock)

        try living.subscriptions.subscribe(blender, avatar: nil)
        try living.watchLater.add(summary(first))
        clock.advance(by: 5)
        try bedroom.subscriptions.subscribe(rick, avatar: nil)
        try bedroom.watchLater.add(summary(second))

        await living.engine.syncAll()
        await bedroom.engine.syncAll()
        await living.engine.syncAll()

        for device in [living, bedroom] {
            #expect(device.subscriptions.channels().map(\.id) == [blender.id, rick.id])
            #expect(device.watchLater.items().map(\.id) == [second, first])
        }
        #expect(try await remote(SubscriptionsDocument.self, worker).entries.count == 2)
    }

    @Test func `a 412 merges with the document in the response and retries`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        let bedroom = Device(worker, clock: clock)
        try living.subscriptions.subscribe(blender, avatar: nil)
        try bedroom.subscriptions.subscribe(rick, avatar: nil)

        // The bedroom TV creates the store between the living room's GET (404) and its PUT.
        try await worker.writeBeforeNextPut(SyncCoding.encode(bedroom.subscriptions.document()), to: .subscriptions)
        #expect(await living.engine.sync(.subscriptions) == .synced(start))
        #expect(await worker.requests == ["GET subscriptions", "PUT subscriptions", "PUT subscriptions"])
        #expect(living.subscriptions.channels().map(\.id) == [blender.id, rick.id])
        #expect(try await remote(SubscriptionsDocument.self, worker).entries.map(\.id).sorted() == [blender.id, rick.id].sorted())
    }

    @Test func `three 412s in a row fail the round without moving lastSyncAt`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        try living.subscriptions.subscribe(blender, avatar: nil)
        for name in ["A", "B", "C"] {
            let other = SubscriptionsDocument(entries: [SubscriptionRecord(id: "UC\(name)", name: name, avatar: nil, changedAt: start)])
            try await worker.writeBeforeNextPut(SyncCoding.encode(other), to: .subscriptions)
        }
        #expect(await living.engine.sync(.subscriptions) == .failed(.conflictPersisted))
        #expect(await worker.requests.count == 1 + SyncEngine.maxAttempts)
        #expect(living.engine.lastSyncAt(.subscriptions) == nil)
        #expect(living.engine.status(.subscriptions) == .failed(.conflictPersisted))

        #expect(await living.engine.sync(.subscriptions) == .synced(start))
        // The failed round saved nothing locally; the Worker now holds only the last foreign write.
        #expect(living.subscriptions.channels().map(\.name) == ["Blender", "C"])
    }

    @Test func `a device offline for 100 days doesn't bring back what was removed elsewhere`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        let bedroom = Device(worker, clock: clock)
        try living.subscriptions.subscribe(blender, avatar: nil)
        try living.watchLater.add(summary(first))
        await living.engine.syncAll()
        clock.advance(by: 60)
        await bedroom.engine.syncAll()
        #expect(bedroom.subscriptions.isSubscribed(blender.id))
        #expect(bedroom.watchLater.contains(first))

        // The bedroom TV stays off; the living room removes both and, 95 days later, prunes the markers.
        clock.advance(by: day)
        try living.subscriptions.unsubscribe(blender.id)
        try living.watchLater.remove(first)
        await living.engine.syncAll()
        clock.advance(by: 50 * day)
        try bedroom.subscriptions.subscribe(rick, avatar: nil) // a change made while offline
        clock.advance(by: 44 * day)
        await living.engine.syncAll()
        #expect(try await remote(SubscriptionsDocument.self, worker).entries.isEmpty)
        #expect(try await remote(WatchLaterDocument.self, worker).entries.isEmpty)

        clock.advance(by: 5 * day)
        await bedroom.engine.syncAll()
        #expect(bedroom.subscriptions.channels().map(\.id) == [rick.id])
        #expect(!bedroom.watchLater.contains(first))
        await living.engine.syncAll()
        #expect(living.subscriptions.channels().map(\.id) == [rick.id])
        #expect(living.watchLater.items().isEmpty)
    }

    @Test func `a newer format on the Worker stops that store without overwriting it`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        let newer = Data(#"{"format":2,"entries":[],"future":true}"#.utf8)
        await worker.write(newer, to: .subscriptions)
        try living.subscriptions.subscribe(blender, avatar: nil)
        try living.watchLater.add(summary(first))

        #expect(await living.engine.sync(.subscriptions) == .failed(.unsupportedFormat(2)))
        #expect(await living.engine.sync(.subscriptions) == .failed(.unsupportedFormat(2)))
        #expect(await worker.requests == ["GET subscriptions"])
        #expect(await worker.data(.subscriptions) == newer)
        #expect(living.subscriptions.isSubscribed(blender.id))

        #expect(await living.engine.sync(.watchLater) == .synced(start))
        #expect(try await remote(WatchLaterDocument.self, worker).entries.count == 1)
    }

    @Test func `an unreadable Worker document is not overwritten`() async throws {
        let worker = FakeWorker()
        let living = Device(worker, clock: TestClock(start))
        await worker.write(Data(#"{"format":1,"entries":"nope"}"#.utf8), to: .subscriptions)
        try living.subscriptions.subscribe(blender, avatar: nil)
        #expect(await living.engine.sync(.subscriptions) == .failed(.invalidDocument(detail: "Worker document unreadable")))
        #expect(await worker.requests == ["GET subscriptions"])
    }

    @Test func `a rejected token stops every store until a new engine is made`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        try living.subscriptions.subscribe(blender, avatar: nil)
        await worker.fail(with: .unauthorized)

        let statuses = await living.engine.syncAll()
        #expect(statuses == Dictionary(uniqueKeysWithValues: SyncStoreName.allCases.map { ($0, SyncEngine.Status.failed(.unauthorized)) }))
        let requestsAfterRejection = await worker.requests.count
        await worker.fail(with: nil)
        #expect(await living.engine.sync(.subscriptions) == .failed(.unauthorized))
        #expect(await worker.requests.count == requestsAfterRejection)
        #expect(living.subscriptions.isSubscribed(blender.id))

        living.relaunch(worker, clock: clock)
        #expect(await living.engine.sync(.subscriptions) == .synced(start))
    }

    @Test func `offline leaves local data untouched and the next sync catches up`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        try living.subscriptions.subscribe(blender, avatar: nil)
        let before = living.subscriptions.document()
        await worker.fail(with: .offline(detail: "timed out"))

        #expect(await living.engine.sync(.subscriptions) == .failed(.offline(detail: "timed out")))
        #expect(living.subscriptions.document() == before)
        #expect(living.engine.lastSyncAt(.subscriptions) == nil)
        #expect(living.takeChanges().isEmpty)

        await worker.fail(with: nil)
        clock.advance(by: 300)
        #expect(await living.engine.sync(.subscriptions) == .synced(start + 300))
        #expect(try await remote(SubscriptionsDocument.self, worker) == before)
    }

    @Test func `clearing history on one device clears it on the other`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        let bedroom = Device(worker, clock: clock)
        try living.history.record(first, position: 120, duration: 600, at: start)
        try bedroom.history.record(second, position: 300, duration: 600, reachedEnd: true, at: start + 1)
        clock.advance(by: 10)
        await living.engine.sync(.history)
        await bedroom.engine.sync(.history)
        await living.engine.sync(.history)
        #expect(living.history.resumePosition(for: first) == 120)
        #expect(bedroom.history.resumePosition(for: first) == 120)
        #expect(living.history.entry(for: second)?.watched == true)
        _ = bedroom.takeChanges()

        clock.advance(by: 10)
        living.history.clear()
        await living.engine.sync(.history)
        clock.advance(by: 10)
        await bedroom.engine.sync(.history)
        #expect(bedroom.history.entries().isEmpty)
        #expect(bedroom.takeChanges() == [.history])
        #expect(try await remote(HistoryDocument.self, worker).clearedAt == start + 20)
    }

    @Test func `the later settings change wins on both devices, restoring defaults included`() async {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        let bedroom = Device(worker, clock: clock)
        var livingSettings = SkipSettings.default
        livingSettings.set(.off, for: .sponsor)
        living.settings.save(livingSettings)
        clock.advance(by: 10)
        var bedroomSettings = SkipSettings.default
        bedroomSettings.set(.off, for: .intro)
        bedroom.settings.save(bedroomSettings)

        await living.engine.sync(.skipSettings)
        await bedroom.engine.sync(.skipSettings)
        await living.engine.sync(.skipSettings)
        #expect(living.settings.load() == bedroomSettings)
        #expect(bedroom.settings.load() == bedroomSettings)

        clock.advance(by: 10)
        living.settings.save(.default)
        await living.engine.sync(.skipSettings)
        await bedroom.engine.sync(.skipSettings)
        #expect(bedroom.settings.load() == .default)
    }

    @Test func `never-written stores with nothing to share are not created`() async {
        let worker = FakeWorker()
        let living = Device(worker, clock: TestClock(start))
        let statuses = await living.engine.syncAll()
        #expect(Set(statuses.values) == [.synced(start)])
        #expect(await worker.requests.sorted() == (SyncStoreName.allCases.map { "GET \($0.rawValue)" } + ["GET inbox"]).sorted())
    }

    @Test func `an unchanged store only reads, and lastSyncAt survives a relaunch`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        try living.subscriptions.subscribe(blender, avatar: nil)
        await living.engine.sync(.subscriptions)
        clock.advance(by: 60)
        await living.engine.sync(.subscriptions)
        #expect(await worker.requests == ["GET subscriptions", "PUT subscriptions", "GET subscriptions"])
        #expect(living.takeChanges().isEmpty)

        living.relaunch(worker, clock: clock)
        #expect(living.engine.lastSyncAt(.subscriptions) == start + 60)
        #expect(living.engine.status(.subscriptions) == .synced(start + 60))
        #expect(living.engine.status(.history) == .notSynced)

        SyncEngine.resetState(in: living.defaults)
        #expect(living.engine.lastSyncAt(.subscriptions) == nil)
    }

    @Test func `a change made while a push is in flight is pushed by the next sync call`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        try living.subscriptions.subscribe(blender, avatar: nil)
        await worker.holdPuts()
        let firstRound = Task { await living.engine.sync(.subscriptions) }
        while await worker.heldPutCount == 0 {
            await Task.yield()
        }
        #expect(living.engine.status(.subscriptions) == .syncing)

        clock.advance(by: 1)
        try living.subscriptions.subscribe(rick, avatar: nil)
        let secondCall = Task { await living.engine.sync(.subscriptions) }
        await Task.yield()
        await worker.releasePuts()

        #expect(await firstRound.value == .synced(start + 1))
        #expect(await secondCall.value == .synced(start + 1))
        #expect(try await remote(SubscriptionsDocument.self, worker).entries.map(\.id).sorted() == [blender.id, rick.id].sorted())
    }

    @Test func `a change in the same millisecond as the round's read survives and is pushed`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        try living.subscriptions.subscribe(blender, avatar: nil)
        await worker.holdPuts()
        let firstRound = Task { await living.engine.sync(.subscriptions) }
        while await worker.heldPutCount == 0 {
            await Task.yield()
        }
        // No clock advance: Rick's changedAt equals the read time that becomes lastSyncAt.
        try living.subscriptions.subscribe(rick, avatar: nil)
        let secondCall = Task { await living.engine.sync(.subscriptions) }
        await Task.yield()
        await worker.releasePuts()

        #expect(await firstRound.value == .synced(start))
        #expect(await secondCall.value == .synced(start))
        #expect(living.subscriptions.channels().map(\.id) == [blender.id, rick.id])
        #expect(try await remote(SubscriptionsDocument.self, worker).entries.map(\.id).sorted() == [blender.id, rick.id].sorted())
    }

    @Test func `a round that fails after its GET saves nothing, so an unsubscribe made meanwhile isn't undone later`() async throws {
        let worker = FakeWorker()
        let clock = TestClock(start)
        let living = Device(worker, clock: clock)
        let bedroom = Device(worker, clock: clock)
        try living.subscriptions.subscribe(blender, avatar: nil)
        await living.engine.sync(.subscriptions)

        // The bedroom TV reads the Worker (Blender), then its PUT of its own change goes nowhere.
        clock.advance(by: 60)
        try bedroom.subscriptions.subscribe(rick, avatar: nil)
        await worker.holdPuts()
        let failing = Task { await bedroom.engine.sync(.subscriptions) }
        while await worker.heldPutCount == 0 {
            await Task.yield()
        }
        await worker.fail(with: .offline(detail: "lost"))
        await worker.releasePuts()
        #expect(await failing.value == .failed(.offline(detail: "lost")))
        #expect(!bedroom.subscriptions.isSubscribed(blender.id))
        await worker.fail(with: nil)

        // The living room unsubscribes; the marker is pruned 100 days later.
        clock.advance(by: 60)
        try living.subscriptions.unsubscribe(blender.id)
        await living.engine.sync(.subscriptions)
        clock.advance(by: 100 * day)
        await living.engine.sync(.subscriptions)
        #expect(try await remote(SubscriptionsDocument.self, worker).entries.map(\.id) == [])

        clock.advance(by: 60)
        await bedroom.engine.sync(.subscriptions)
        await living.engine.sync(.subscriptions)
        for device in [living, bedroom] {
            #expect(!device.subscriptions.isSubscribed(blender.id))
            #expect(device.subscriptions.isSubscribed(rick.id))
        }
    }

    @Test func `a weak ETag from the GET goes back verbatim in If-Match`() async throws {
        let worker = FakeWorker()
        await worker.useWeakETags()
        let living = Device(worker, clock: TestClock(start))
        try living.subscriptions.subscribe(blender, avatar: nil)
        await living.engine.sync(.subscriptions)
        try living.subscriptions.subscribe(rick, avatar: nil)
        #expect(await living.engine.sync(.subscriptions) == .synced(start))
        #expect(await worker.preconditions == [.create, .replace(#"W/"1""#)])
    }
}
