import Foundation
import os

/// The Contract of the household's sync Worker (`FooTubeSyncBackend/SPEC.md`): one opaque JSON
/// document per store, read with `GET /v1/stores/:name` and written with a conditional
/// `PUT /v1/stores/:name`. ETags are passed through verbatim; the client never parses them.
public struct SyncClient: Sendable {
    /// What the client last saw of the store, sent as the `PUT` precondition.
    public enum Precondition: Hashable, Sendable {
        /// `If-None-Match: *`: the store was never written (`fetch` returned nil).
        case create
        /// `If-Match: <ETag>`: replace the version with this ETag.
        case replace(String)
    }

    public enum PutResult: Hashable, Sendable {
        /// Written; the store's new ETag.
        case stored(String)
        /// `412`: another device wrote first. The current document and its ETag, both nil when the
        /// store doesn't exist (a `.replace` of a store that was never written).
        case conflict(data: Data?, etag: String?)
    }

    /// The Worker refuses documents larger than this (`413`).
    public static let maxDocumentBytes = 1024 * 1024

    private let baseURL: URL
    private let token: String
    private let session: URLSession
    private let timeout: Duration
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "sync")

    public init(baseURL: URL, token: String, session: URLSession = .shared, timeout: Duration = .seconds(10)) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
        self.timeout = timeout
    }

    /// The store's document and ETag, or nil when it was never written (`404`).
    public func fetch(_ store: SyncStoreName) async throws(SyncError) -> (data: Data, etag: String)? {
        let (data, response) = try await send(request(for: store, method: "GET"), label: store.rawValue)
        switch response.statusCode {
        case 200:
            guard let etag = response.value(forHTTPHeaderField: "ETag") else { throw .server(status: 200) }
            return (data, etag)
        case 404:
            return nil
        case 401:
            throw .unauthorized
        default:
            throw .server(status: response.statusCode)
        }
    }

    /// Writes the whole document if the precondition still holds on the Worker.
    public func put(_ store: SyncStoreName, data: Data, precondition: Precondition) async throws(SyncError) -> PutResult {
        var request = request(for: store, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch precondition {
        case .create: request.setValue("*", forHTTPHeaderField: "If-None-Match")
        case let .replace(etag): request.setValue(etag, forHTTPHeaderField: "If-Match")
        }
        request.httpBody = data
        let (body, response) = try await send(request, label: store.rawValue)
        switch response.statusCode {
        case 200:
            guard let etag = response.value(forHTTPHeaderField: "ETag") else { throw .server(status: 200) }
            return .stored(etag)
        case 412:
            return .conflict(data: body.isEmpty ? nil : body, etag: response.value(forHTTPHeaderField: "ETag"))
        case 401:
            throw .unauthorized
        default:
            throw .server(status: response.statusCode)
        }
    }

    /// The browser inbox (SPEC-browser-inbox), oldest first; nil when this Worker has no inbox:
    /// `500 not_configured` (no `INBOX_TOKEN` set) or `404` (a Worker from before the inbox).
    public func inbox() async throws(SyncError) -> [InboxItem]? {
        let (data, response) = try await send(request(path: "v1/inbox", method: "GET"), label: "inbox")
        switch response.statusCode {
        case 200:
            guard let list = try? SyncCoding.decoder().decode(InboxList.self, from: data) else {
                throw .invalidDocument(detail: "inbox unreadable")
            }
            return list.items
        case 404:
            return nil
        case 500 where (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error == "not_configured":
            return nil
        case 401:
            throw .unauthorized
        default:
            throw .server(status: response.statusCode)
        }
    }

    /// Removes the inbox items up to and including `seq` (idempotent).
    public func clearInbox(through seq: Int) async throws(SyncError) {
        var request = request(path: "v1/inbox", method: "DELETE")
        request.url = request.url?.appending(queryItems: [URLQueryItem(name: "through", value: String(seq))])
        let (_, response) = try await send(request, label: "inbox")
        switch response.statusCode {
        case 204: return
        case 401: throw .unauthorized
        default: throw .server(status: response.statusCode)
        }
    }

    private struct InboxList: Decodable {
        let items: [InboxItem]
    }

    private struct ErrorBody: Decodable {
        let error: String
    }

    private func request(for store: SyncStoreName, method: String) -> URLRequest {
        request(path: "v1/stores/\(store.rawValue)", method: method)
    }

    private func request(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = Double(timeout.components.seconds)
        // Documents change on other devices; never answer a GET from URLCache.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Logs method, store (or `inbox`) and status only: never the token, headers, documents or videos.
    private func send(_ request: URLRequest, label: String) async throws(SyncError) -> (Data, HTTPURLResponse) {
        let method = request.httpMethod ?? "GET"
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            let detail = (error as? URLError).map { "\($0.localizedDescription) (\($0.code.rawValue))" } ?? String(describing: type(of: error))
            logger.error("\(method, privacy: .public) \(label, privacy: .public): offline (\(detail, privacy: .public))")
            throw .offline(detail: detail)
        }
        guard let response = result.1 as? HTTPURLResponse else {
            logger.error("\(method, privacy: .public) \(label, privacy: .public): not an HTTP response")
            throw .server(status: 0)
        }
        logger.info("\(method, privacy: .public) \(label, privacy: .public): HTTP \(response.statusCode)")
        return (result.0, response)
    }
}
