import Foundation

/// Why a sync request or round failed. `SyncClient` throws the first three and `invalidDocument` (an
/// unreadable or oversized response); the engine adds the rest.
public enum SyncError: Error, Hashable, Sendable {
    /// No answer from the Worker: no network, DNS, TLS, connection refused or the 10 s timeout.
    case offline(detail: String)
    /// `401`: the Worker rejected the token.
    case unauthorized
    /// A `5xx` or any status the Contract doesn't allow for the request (also a `200` without `ETag`).
    case server(status: Int)
    /// The Worker's document has a `format` newer than this build knows.
    case unsupportedFormat(Int)
    /// Every attempt of a round ended in `412`.
    case conflictPersisted
    /// The Worker's document or response can't be read (no `format`, wrong fields, over the size or
    /// item limits), or the local one can't be written; the round stops without overwriting anything
    /// on the Worker.
    case invalidDocument(detail: String)
    /// The merged document is over `SyncClient.maxDocumentBytes`; the round stops before the `PUT`
    /// (the Worker would refuse it with `413`) and local data stays as it was.
    case documentTooLarge(bytes: Int)

    public var message: String {
        switch self {
        case let .offline(detail): "Sync Worker unreachable: \(detail)"
        case .unauthorized: "Sync Worker rejected the token"
        case let .server(status): "Sync Worker answered HTTP \(status)"
        case let .unsupportedFormat(format): "Sync document has format \(format), newer than this build"
        case .conflictPersisted: "Sync kept conflicting with other devices"
        case let .invalidDocument(detail): "Sync document invalid: \(detail)"
        case let .documentTooLarge(bytes): "Sync document is \(bytes) bytes, over the Worker's limit of \(SyncClient.maxDocumentBytes); not sent"
        }
    }
}
