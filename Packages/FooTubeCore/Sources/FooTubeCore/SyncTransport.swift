import Foundation

/// The Worker Contract as `SyncEngine` uses it; `SyncClient` is the real one, tests use an in-memory
/// Worker.
public protocol SyncTransport: Sendable {
    /// The store's document and ETag, or nil when it was never written.
    func fetch(_ store: SyncStoreName) async throws(SyncError) -> (data: Data, etag: String)?
    /// Writes the whole document if the precondition still holds.
    func put(_ store: SyncStoreName, data: Data, precondition: SyncClient.Precondition) async throws(SyncError) -> SyncClient.PutResult
    /// The browser inbox, oldest first; nil when the Worker has none.
    func inbox() async throws(SyncError) -> [InboxItem]?
    /// Removes the inbox items up to and including `seq`.
    func clearInbox(through seq: Int) async throws(SyncError)
}

extension SyncClient: SyncTransport {}
