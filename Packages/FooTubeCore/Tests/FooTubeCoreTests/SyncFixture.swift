import Foundation
import Testing

/// HTTP exchanges with the sync Worker in `Fixtures/sync/`, written by `scripts/record-sync-fixtures.mjs`.
struct SyncFixture: Decodable {
    struct Exchange: Decodable {
        struct Request: Decodable {
            let method: String
            let path: String
            let headers: [String: String]
            /// Omitted for large bodies.
            let body: String?
            let bodyBytes: Int
        }

        struct Response: Decodable {
            let status: Int
            let headers: [String: String]
            let body: String
        }

        let name: String
        let request: Request
        let response: Response

        /// The recorded response, for `StubURLProtocol` to replay.
        var reply: StubURLProtocol.Reply {
            .response(status: response.status, headers: response.headers, body: Data(response.body.utf8))
        }

        /// The recorded request body; nil when it was too large to record.
        var requestBody: Data? {
            request.body.map { Data($0.utf8) }
        }
    }

    let source: String
    let exchanges: [Exchange]

    init(_ name: String) throws {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/sync"))
        self = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func exchange(_ name: String) throws -> Exchange {
        try #require(exchanges.first { $0.name == name }, "no exchange \(name) in fixture")
    }
}
