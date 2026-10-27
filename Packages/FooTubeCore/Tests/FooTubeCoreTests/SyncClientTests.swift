import FooTubeCore
import Foundation
import Testing

/// SyncClient against a URLProtocol stub that replays responses recorded from `wrangler dev`
/// (`Fixtures/sync/`, the Contract in `FooTubeSyncBackend/SPEC.md`).
@Suite("Sync client")
struct SyncClientTests {
    static let token = "test-token-0123456789"

    let example: SyncFixture
    let errors: SyncFixture

    init() throws {
        example = try SyncFixture("example")
        errors = try SyncFixture("errors")
    }

    private func client(_ server: StubURLProtocol.Server) -> SyncClient {
        SyncClient(baseURL: server.baseURL, token: Self.token, session: server.session)
    }

    /// Runs `operation` and returns the `SyncError` it threw, or nil if it didn't throw.
    private func syncError(_ operation: () async throws(SyncError) -> some Any) async -> SyncError? {
        do {
            _ = try await operation()
            return nil
        } catch {
            return error
        }
    }

    // MARK: The Contract's Example

    @Test func `the Contract example: create, replace, stale replace, read`() async throws {
        let steps = try ["get-never-written", "put-create", "put-replace", "put-replace-stale", "get-written"].map(example.exchange)
        let server = StubURLProtocol.Server(steps.map(\.reply))
        let client = client(server)
        let documentA = try #require(steps[1].requestBody)
        let documentB = try #require(steps[2].requestBody)
        let documentC = try #require(steps[3].requestBody)
        let first = try #require(steps[1].response.headers["etag"])
        let second = try #require(steps[2].response.headers["etag"])
        #expect(first != second)

        #expect(try await client.fetch(.subscriptions) == nil)
        #expect(try await client.put(.subscriptions, data: documentA, precondition: .create) == .stored(first))
        #expect(try await client.put(.subscriptions, data: documentB, precondition: .replace(first)) == .stored(second))
        #expect(try await client.put(.subscriptions, data: documentC, precondition: .replace(first)) == .conflict(data: documentB, etag: second))
        let current = try #require(try await client.fetch(.subscriptions))
        #expect(current.data == documentB)
        #expect(current.etag == second)

        let requests = server.requests
        #expect(requests.map(\.method) == steps.map(\.request.method))
        #expect(requests.map(\.path) == steps.map(\.request.path))
        #expect(requests.map(\.body) == [Data(), documentA, documentB, documentC, Data()])
        for (request, step) in zip(requests, steps) {
            #expect(request.header("Authorization") == "Bearer \(Self.token)")
            #expect(request.header("If-Match") == step.request.headers["if-match"])
            #expect(request.header("If-None-Match") == step.request.headers["if-none-match"])
            #expect(request.header("Content-Type") == step.request.headers["content-type"])
            #expect(request.timeout == 10)
        }
    }

    // MARK: Requests

    @Test(arguments: SyncStoreName.allCases)
    func `every store is addressed by its name under v1 stores`(store: SyncStoreName) async throws {
        let server = StubURLProtocol.Server([.response(status: 404)])
        _ = try await client(server).fetch(store)
        #expect(server.requests.map(\.path) == ["/v1/stores/\(store.rawValue)"])
    }

    @Test func `a base URL with a path keeps it`() async throws {
        let server = StubURLProtocol.Server([.response(status: 404)])
        let client = SyncClient(baseURL: server.baseURL.appending(path: "footube"), token: Self.token, session: server.session)
        _ = try await client.fetch(.history)
        #expect(server.requests.map(\.path) == ["/footube/v1/stores/history"])
    }

    @Test func `GET sends no precondition and no content type`() async throws {
        let server = StubURLProtocol.Server([.response(status: 404)])
        _ = try await client(server).fetch(.watchLater)
        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.header("If-Match") == nil)
        #expect(request.header("If-None-Match") == nil)
        #expect(request.header("Content-Type") == nil)
    }

    @Test func `create sends If-None-Match star and no If-Match`() async throws {
        let server = StubURLProtocol.Server([.response(status: 200, headers: ["ETag": "\"1\""])])
        _ = try await client(server).put(.skipSettings, data: Data("{}".utf8), precondition: .create)
        let request = try #require(server.requests.first)
        #expect(request.method == "PUT")
        #expect(request.header("If-None-Match") == "*")
        #expect(request.header("If-Match") == nil)
        #expect(request.header("Content-Type") == "application/json")
    }

    @Test func `ETags travel verbatim in both directions`() async throws {
        let weak = #"W/"7-a1""#
        let server = StubURLProtocol.Server([
            .response(status: 200, headers: ["ETag": weak], body: Data("{}".utf8)),
            .response(status: 200, headers: ["ETag": #""opaque/8""#]),
        ])
        let client = client(server)
        let read = try #require(try await client.fetch(.history))
        #expect(read.etag == weak)
        #expect(try await client.put(.history, data: read.data, precondition: .replace(read.etag)) == .stored(#""opaque/8""#))
        #expect(server.requests.last?.header("If-Match") == weak)
        #expect(server.requests.last?.header("If-None-Match") == nil)
    }

    // MARK: Responses

    @Test func `create on an existing store returns its document and ETag`() async throws {
        let exchange = try errors.exchange("put-create-existing")
        let server = StubURLProtocol.Server([exchange.reply])
        let result = try await client(server).put(.subscriptions, data: Data("{}".utf8), precondition: .create)
        let etag = try #require(exchange.response.headers["etag"])
        #expect(result == .conflict(data: Data(exchange.response.body.utf8), etag: etag))
    }

    @Test func `replace of a never-written store conflicts without document or ETag`() async throws {
        let exchange = try errors.exchange("put-replace-never-written")
        #expect(exchange.response.status == 412)
        let server = StubURLProtocol.Server([exchange.reply])
        let result = try await client(server).put(.watchLater, data: Data("{}".utf8), precondition: .replace(#""1""#))
        #expect(result == .conflict(data: nil, etag: nil))
    }

    @Test(arguments: ["get-unauthorized", "put-unauthorized"])
    func `a rejected token throws unauthorized`(name: String) async throws {
        let exchange = try errors.exchange(name)
        #expect(exchange.response.status == 401)
        let server = StubURLProtocol.Server([exchange.reply, exchange.reply])
        let client = client(server)
        #expect(await syncError { () async throws(SyncError) in try await client.fetch(.subscriptions) } == .unauthorized)
        #expect(await syncError { () async throws(SyncError) in
            try await client.put(.subscriptions, data: Data("{}".utf8), precondition: .create)
        } == .unauthorized)
    }

    @Test(arguments: ["put-no-precondition", "put-no-length", "put-too-large", "put-wrong-type", "delete-not-allowed", "get-not-configured"])
    func `other Contract errors throw server with their status`(name: String) async throws {
        let exchange = try errors.exchange(name)
        let server = StubURLProtocol.Server([exchange.reply, exchange.reply])
        let client = client(server)
        let expected = SyncError.server(status: exchange.response.status)
        #expect(await syncError { () async throws(SyncError) in try await client.fetch(.subscriptions) } == expected)
        #expect(await syncError { () async throws(SyncError) in
            try await client.put(.subscriptions, data: Data("{}".utf8), precondition: .replace(#""2""#))
        } == expected)
    }

    @Test(arguments: [500, 502, 503, 404])
    func `unexpected statuses on PUT throw server`(status: Int) async {
        let server = StubURLProtocol.Server([.response(status: status)])
        let client = client(server)
        #expect(await syncError { () async throws(SyncError) in
            try await client.put(.subscriptions, data: Data("{}".utf8), precondition: .create)
        } == .server(status: status))
    }

    @Test(arguments: [412, 500, 503])
    func `unexpected statuses on GET throw server`(status: Int) async {
        let server = StubURLProtocol.Server([.response(status: status)])
        let client = client(server)
        #expect(await syncError { () async throws(SyncError) in try await client.fetch(.subscriptions) } == .server(status: status))
    }

    @Test func `a 200 without ETag is a server error, not a version`() async {
        let server = StubURLProtocol.Server([.response(status: 200, body: Data("{}".utf8)), .response(status: 200)])
        let client = client(server)
        #expect(await syncError { () async throws(SyncError) in try await client.fetch(.subscriptions) } == .server(status: 200))
        #expect(await syncError { () async throws(SyncError) in
            try await client.put(.subscriptions, data: Data("{}".utf8), precondition: .create)
        } == .server(status: 200))
    }

    @Test(arguments: [URLError.Code.timedOut, .notConnectedToInternet, .cannotConnectToHost, .networkConnectionLost, .secureConnectionFailed])
    func `network failures and timeouts throw offline`(code: URLError.Code) async {
        let server = StubURLProtocol.Server([.failure(code), .failure(code)])
        let client = client(server)
        let fetchError = await syncError { () async throws(SyncError) in try await client.fetch(.subscriptions) }
        let putError = await syncError { () async throws(SyncError) in
            try await client.put(.subscriptions, data: Data("{}".utf8), precondition: .create)
        }
        for error in [fetchError, putError] {
            guard case let .offline(detail) = error else {
                Issue.record("expected offline, got \(String(describing: error))")
                continue
            }
            #expect(detail.contains("(\(code.rawValue))"))
        }
    }

    @Test func `a weak ETag from the edge is returned and sent back verbatim`() async throws {
        let server = StubURLProtocol.Server([
            .response(status: 200, headers: ["ETag": #"W/"7""#, "Content-Type": "application/json"], body: Data(#"{"format":1,"entries":[]}"#.utf8)),
            .response(status: 200, headers: ["ETag": #""8""#]),
        ])
        let client = client(server)
        let fetched = try #require(try await client.fetch(.subscriptions))
        #expect(fetched.etag == #"W/"7""#)
        #expect(try await client.put(.subscriptions, data: fetched.data, precondition: .replace(fetched.etag)) == .stored(#""8""#))
        #expect(server.requests.last?.header("If-Match") == #"W/"7""#)
    }

    // MARK: Browser inbox

    @Test func `the inbox is read with the sync token, oldest first, dates with milliseconds`() async throws {
        let body = #"{"items":[{"seq":3,"videoID":"aqz-KE-bpKQ","title":"Big Buck Bunny","addedAt":"2027-01-15T08:00:00.123Z"},{"seq":5,"videoID":"aiDHXKRxLeQ","addedAt":"2027-01-15T08:01:00.000Z"}]}"#
        let server = StubURLProtocol.Server([.response(status: 200, headers: ["Content-Type": "application/json"], body: Data(body.utf8))])
        let items = try await client(server).inbox()
        #expect(items == [
            InboxItem(seq: 3, videoID: "aqz-KE-bpKQ", title: "Big Buck Bunny", addedAt: Date(timeIntervalSince1970: 1_800_000_000.123)),
            InboxItem(seq: 5, videoID: "aiDHXKRxLeQ", title: nil, addedAt: Date(timeIntervalSince1970: 1_800_000_060)),
        ])
        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.path == "/v1/inbox")
        #expect(request.header("Authorization") == "Bearer \(Self.token)")
    }

    @Test(arguments: [
        (500, #"{"error":"not_configured","message":"INBOX_TOKEN is not set"}"#),
        (404, #"{"error":"not_found","message":"no such route"}"#),
    ])
    func `a Worker without an inbox answers nil`(status: Int, body: String) async throws {
        let server = StubURLProtocol.Server([.response(status: status, body: Data(body.utf8))])
        #expect(try await client(server).inbox() == nil)
    }

    @Test func `other inbox errors are errors`() async {
        let server = StubURLProtocol.Server([
            .response(status: 500, body: Data(#"{"error":"internal","message":"boom"}"#.utf8)),
            .response(status: 401),
            .response(status: 200, body: Data("not json".utf8)),
        ])
        let client = client(server)
        #expect(await syncError { () async throws(SyncError) in try await client.inbox() } == .server(status: 500))
        #expect(await syncError { () async throws(SyncError) in try await client.inbox() } == .unauthorized)
        #expect(await syncError { () async throws(SyncError) in try await client.inbox() } == .invalidDocument(detail: "inbox unreadable"))
    }

    @Test func `clearing the inbox deletes through a sequence number`() async throws {
        let server = StubURLProtocol.Server([.response(status: 204), .response(status: 401), .response(status: 400)])
        let client = client(server)
        try await client.clearInbox(through: 7)
        #expect(await syncError { () async throws(SyncError) in try await client.clearInbox(through: 7) } == .unauthorized)
        #expect(await syncError { () async throws(SyncError) in try await client.clearInbox(through: 7) } == .server(status: 400))
        let request = try #require(server.requests.first)
        #expect(request.method == "DELETE")
        #expect(request.path == "/v1/inbox")
        #expect(request.query == "through=7")
        #expect(request.header("Authorization") == "Bearer \(Self.token)")
    }
}
