import Foundation
import Synchronization

/// Serves canned HTTP replies to a `URLSession` and records the requests it got. Every `Server` has
/// its own host, so tests running in parallel never see each other's replies or requests.
final class StubURLProtocol: URLProtocol {
    enum Reply: Sendable {
        case response(status: Int, headers: [String: String] = [:], body: Data = Data())
        /// A redirect to `location` (another `Server`'s URL to see whether it is followed); the new
        /// request keeps every header, as URLSession's own redirects do.
        case redirect(status: Int, location: URL)
        case failure(URLError.Code)
    }

    struct Request: Sendable {
        let method: String
        let path: String
        let query: String?
        let headers: [String: String]
        let body: Data
        let timeout: TimeInterval

        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    /// A stub host whose session answers with `replies` in order, one per request.
    struct Server: Sendable {
        let baseURL: URL
        let session: URLSession
        private let host: String

        init(_ replies: [Reply]) {
            host = "stub-\(UUID().uuidString.lowercased()).invalid"
            baseURL = URL(string: "https://\(host)")!
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            session = URLSession(configuration: configuration)
            StubURLProtocol.routes.withLock { [host] in $0[host] = Route(replies: replies) }
        }

        /// The requests the server got so far, in order.
        var requests: [Request] {
            StubURLProtocol.routes.withLock { [host] in $0[host]?.requests ?? [] }
        }
    }

    private struct Route {
        var replies: [Reply]
        var requests: [Request] = []
    }

    private static let routes = Mutex<[String: Route]>([:])

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let recorded = Request(
            method: request.httpMethod ?? "GET",
            path: request.url?.path ?? "",
            query: request.url?.query,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? request.httpBodyStream.map(Self.readAll) ?? Data(),
            timeout: request.timeoutInterval,
        )
        let host = request.url?.host ?? ""
        let reply = Self.routes.withLock { routes -> Reply in
            routes[host]?.requests.append(recorded)
            guard let next = routes[host]?.replies.first else { return .failure(.resourceUnavailable) }
            routes[host]?.replies.removeFirst()
            return next
        }
        switch reply {
        case let .response(status, headers, body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .redirect(status, location):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Location": location.absoluteString])!
            var next = request
            next.url = location
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            // What the client gets when it refuses the redirect: the 3xx itself.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}

    /// URLSession hands a body set with `httpBody` to protocols as a stream.
    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
