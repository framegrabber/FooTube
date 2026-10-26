import FooTubeCore
import Foundation
import Testing

/// Runs the Contract's Example against a real sync Worker. Opt-in, and only against `wrangler dev`
/// (it writes the Worker's `subscriptions` store; never point it at the household's Worker):
/// `(cd ../FooTubeSyncBackend && npm run dev)`, then
/// `FOOTUBE_SYNC_URL=http://localhost:8787 FOOTUBE_SYNC_TOKEN=<token from its .dev.vars> swift test --package-path Packages/FooTubeCore --filter SyncNetworkTests`.
@Suite(
    "SyncClient against wrangler dev",
    .enabled(if: ProcessInfo.processInfo.environment["FOOTUBE_SYNC_URL"] != nil
        && ProcessInfo.processInfo.environment["FOOTUBE_SYNC_TOKEN"] != nil),
    .serialized,
)
struct SyncNetworkTests {
    let baseURL: URL
    let token: String

    init() throws {
        let environment = ProcessInfo.processInfo.environment
        baseURL = try #require(environment["FOOTUBE_SYNC_URL"].flatMap(URL.init(string:)))
        token = try #require(environment["FOOTUBE_SYNC_TOKEN"])
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
