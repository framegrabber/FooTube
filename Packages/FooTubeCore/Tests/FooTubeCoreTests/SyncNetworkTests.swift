import FooTubeCore
import Foundation
import Testing

/// Runs the Contract's Example against a real sync Worker. Opt-in, and only against `wrangler dev`
/// (it writes the Worker's stores; never point it at the household's Worker):
/// `(cd ../FooTubeSyncBackend && npm run dev)`, then
/// `FOOTUBE_SYNC_TEST_URL=http://localhost:8787 FOOTUBE_SYNC_TEST_TOKEN=<token from its .dev.vars> swift test --package-path Packages/FooTubeCore --filter SyncNetworkTests`.
/// Own variable names, not the run scripts' `FOOTUBE_SYNC_URL`/`FOOTUBE_SYNC_TOKEN`, and loopback
/// hosts only, so a shell set up to run the app against the household's Worker never runs this.
private let localWorker: (url: URL, token: String)? = {
    let environment = ProcessInfo.processInfo.environment
    guard let url = environment["FOOTUBE_SYNC_TEST_URL"].flatMap(URL.init(string:)),
          let token = environment["FOOTUBE_SYNC_TEST_TOKEN"],
          ["localhost", "127.0.0.1"].contains(url.host()) else { return nil }
    return (url, token)
}()

@Suite(
    "SyncClient against wrangler dev",
    .enabled(if: localWorker != nil),
    .serialized,
)
struct SyncNetworkTests {
    let baseURL: URL
    let token: String

    init() throws {
        let worker = try #require(localWorker)
        baseURL = worker.url
        token = worker.token
    }

    /// A subscriptions document whose only entry is a removal marker, so the app hides it if a
    /// Simulator later syncs with the same `wrangler dev`. Non-ASCII to check byte-for-byte storage.
    private static func document(_ label: String, at date: Date) -> Data {
        let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
        return Data(#"{"format":1,"entries":[{"id":"UCsyncNetworkTest","name":"\#(label) – Grüße","changedAt":"\#(stamp)","removedAt":"\#(stamp)"}]}"#.utf8)
    }

    /// The Example, starting from whatever the store holds so it can run more than once.
    @Test func `create or replace, replace, stale replace and read follow the Contract`() async throws {
        let client = SyncClient(baseURL: baseURL, token: token)
        let now = Date()
        let documentA = Self.document("A", at: now)
        let documentB = Self.document("B", at: now)
        let documentC = Self.document("C", at: now)

        let start = try await client.fetch(.subscriptions)
        let precondition: SyncClient.Precondition = start.map { .replace($0.etag) } ?? .create
        guard case let .stored(first) = try await client.put(.subscriptions, data: documentA, precondition: precondition) else {
            Issue.record("first write conflicted; is another client writing to this Worker?")
            return
        }
        guard case let .stored(second) = try await client.put(.subscriptions, data: documentB, precondition: .replace(first)) else {
            Issue.record("second write conflicted")
            return
        }
        #expect(second != first)
        #expect(try await client.put(.subscriptions, data: documentC, precondition: .replace(first)) == .conflict(data: documentB, etag: second))
        #expect(try await client.put(.subscriptions, data: documentC, precondition: .create) == .conflict(data: documentB, etag: second))
        let current = try #require(try await client.fetch(.subscriptions))
        #expect(current.data == documentB)
        #expect(current.etag == second)
    }

    /// Two devices (own `UserDefaults` suites and engines) against the Worker: subscribe on one, see it
    /// on the other, unsubscribe there, see it gone on the first. Leaves only a removal marker.
    @MainActor
    @Test func `two devices sync a subscribe and an unsubscribe through the Worker`() async throws {
        func device() throws -> (SubscriptionStore, SyncEngine) {
            let suite = "footube-network-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defaults.removePersistentDomain(forName: suite)
            let subscriptions = SubscriptionStore(defaults: defaults)
            let engine = SyncEngine(
                transport: SyncClient(baseURL: baseURL, token: token),
                subscriptions: subscriptions,
                watchLater: WatchLaterStore(defaults: defaults),
                history: WatchHistory(defaults: defaults),
                skipSettings: SkipSettingsStore(defaults: defaults),
                defaults: defaults,
            )
            return (subscriptions, engine)
        }
        let (livingStore, living) = try device()
        let (bedroomStore, bedroom) = try device()
        let channel = ChannelRef(id: "UCsyncNetwork\(UUID().uuidString.prefix(8))", name: "Network test – Grüße")

        try livingStore.subscribe(channel, avatar: nil)
        guard case .synced = await living.sync(.subscriptions) else {
            Issue.record("living room round failed: \(living.status(.subscriptions))")
            return
        }
        guard case .synced = await bedroom.sync(.subscriptions) else {
            Issue.record("bedroom round failed: \(bedroom.status(.subscriptions))")
            return
        }
        #expect(bedroomStore.isSubscribed(channel.id))

        try bedroomStore.unsubscribe(channel.id)
        guard case .synced = await bedroom.sync(.subscriptions) else {
            Issue.record("bedroom push failed: \(bedroom.status(.subscriptions))")
            return
        }
        guard case .synced = await living.sync(.subscriptions) else {
            Issue.record("living room pull failed: \(living.status(.subscriptions))")
            return
        }
        #expect(!livingStore.isSubscribed(channel.id))
    }

    @Test func `a wrong token is rejected on read and write`() async {
        let client = SyncClient(baseURL: baseURL, token: "wrong-\(UUID().uuidString)")
        await #expect(throws: SyncError.unauthorized) { try await client.fetch(.subscriptions) }
        await #expect(throws: SyncError.unauthorized) {
            try await client.put(.subscriptions, data: Self.document("wrong token", at: Date()), precondition: .create)
        }
    }

    @Test func `an unreachable Worker is offline quickly`() async throws {
        let client = try SyncClient(baseURL: #require(URL(string: "http://127.0.0.1:9")), token: token, timeout: .seconds(2))
        let started = ContinuousClock.now
        await #expect {
            try await client.fetch(.subscriptions)
        } throws: { error in
            if case .offline = error as? SyncError {
                true
            } else {
                false
            }
        }
        #expect(ContinuousClock.now - started < .seconds(5))
    }
}
