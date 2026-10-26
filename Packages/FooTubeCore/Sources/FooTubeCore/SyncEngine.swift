import Foundation
import os

/// Syncs the four local stores with the household's Worker (SPEC-sync-client → Sync engine). Knows
/// nothing about when to sync: the app calls `sync(_:)`/`syncAll()` on its triggers.
///
/// One round per store: `GET` → merge with the local document → save locally if that changed
/// (`onLocalChange`) → `PUT` if the merged document differs from the Worker's (`If-Match`, or
/// `If-None-Match: *` after a `404`) → on `412` merge again with the document in the response, at most
/// `maxAttempts` times → `lastSyncAt` = when the local document was read for the merge that reached
/// the Worker. Local read, merge and save happen without suspending, on the main actor where every
/// store write happens, so a change made while a request is in flight is never lost; its own round
/// pushes it.
@MainActor
public final class SyncEngine {
    /// Where one store's sync stands on this device.
    public enum Status: Hashable, Sendable {
        /// Never completed a round on this device.
        case notSynced
        case syncing
        /// The last round succeeded; the store's `lastSyncAt`.
        case synced(Date)
        /// The last round failed. `.unauthorized` stops every store and `.unsupportedFormat` that
        /// store until a new engine is made (new configuration or launch); other errors retry on the
        /// next call.
        case failed(SyncError)
    }

    public static let maxAttempts = 3
    /// Per store `lastSyncAt`, in the engine's `UserDefaults`.
    public static let stateKey = "sync.state.v1"

    private let transport: any SyncTransport
    private let subscriptions: SubscriptionStore
    private let watchLater: WatchLaterStore
    private let history: WatchHistory
    private let skipSettings: SkipSettingsStore
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let onLocalChange: @MainActor (SyncStoreName) -> Void
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "sync")

    private var statuses: [SyncStoreName: Status] = [:]
    private var running: [SyncStoreName: Task<Status, Never>] = [:]
    private var rerun: Set<SyncStoreName> = []
    private var rejected = false
    private var unsupported: [SyncStoreName: Int] = [:]

    /// `onLocalChange` runs after a merge changed a store's local document, so models reload it.
    public init(
        transport: any SyncTransport,
        subscriptions: SubscriptionStore,
        watchLater: WatchLaterStore,
        history: WatchHistory,
        skipSettings: SkipSettingsStore,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { .now },
        onLocalChange: @escaping @MainActor (SyncStoreName) -> Void = { _ in },
    ) {
        self.transport = transport
        self.subscriptions = subscriptions
        self.watchLater = watchLater
        self.history = history
        self.skipSettings = skipSettings
        self.defaults = defaults
        self.now = now
        self.onLocalChange = onLocalChange
    }

    /// Forgets every store's `lastSyncAt` (`-syncReset`); the next round unions local data with the
    /// Worker's like a first sync.
    public static func resetState(in defaults: UserDefaults) {
        defaults.removeObject(forKey: stateKey)
    }

    public func status(_ store: SyncStoreName) -> Status {
        statuses[store] ?? lastSyncAt(store).map(Status.synced) ?? .notSynced
    }

    /// When the store's local document was read for the last merge that reached the Worker.
    public func lastSyncAt(_ store: SyncStoreName) -> Date? {
        loadState()[store.rawValue]?.lastSyncAt
    }

    /// Runs a round for `store`. While one is in flight, waits for it and runs one more afterwards, so
    /// changes made meanwhile are pushed.
    @discardableResult
    public func sync(_ store: SyncStoreName) async -> Status {
        if let task = running[store] {
            rerun.insert(store)
            return await task.value
        }
        let task = Task { await self.rounds(store) }
        running[store] = task
        return await task.value
    }

    /// Syncs the four stores concurrently.
    @discardableResult
    public func syncAll() async -> [SyncStoreName: Status] {
        await withTaskGroup(of: (SyncStoreName, Status).self) { group in
            for store in SyncStoreName.allCases {
                group.addTask { await (store, self.sync(store)) }
            }
            var result: [SyncStoreName: Status] = [:]
            for await (store, status) in group {
                result[store] = status
            }
            return result
        }
    }

    private func rounds(_ store: SyncStoreName) async -> Status {
        var status: Status
        repeat {
            rerun.remove(store)
            status = await round(store)
        } while rerun.contains(store) && !status.isFailure
        rerun.remove(store)
        running[store] = nil
        return status
    }

    private func round(_ store: SyncStoreName) async -> Status {
        if rejected {
            return .failed(.unauthorized)
        }
        if let format = unsupported[store] {
            return .failed(.unsupportedFormat(format))
        }
        statuses[store] = .syncing
        let status: Status
        do throws(SyncError) {
            let syncedAt = switch store {
            case .subscriptions: try await round(store, subscriptions)
            case .watchLater: try await round(store, watchLater)
            case .history: try await round(store, history)
            case .skipSettings: try await round(store, skipSettings)
            }
            status = .synced(syncedAt)
        } catch {
            switch error {
            case .unauthorized: rejected = true
            case let .unsupportedFormat(format): unsupported[store] = format
            default: break
            }
            logger.error("\(store.rawValue, privacy: .public): \(error.message, privacy: .public)")
            status = .failed(error)
        }
        statuses[store] = status
        return status
    }

    /// Returns the new `lastSyncAt`.
    private func round<Store: SyncableStore>(_ name: SyncStoreName, _ store: Store) async throws(SyncError) -> Date {
        var remote = try await transport.fetch(name)
        for attempt in 1 ... Self.maxAttempts {
            var remoteDocument: Store.Document?
            if let remote {
                remoteDocument = try decode(Store.Document.self, from: remote.data)
            }
            let readAt = SyncCoding.timestamp(now())
            let local = store.document()
            let merged = local.merged(with: remoteDocument, lastSyncAt: lastSyncAt(name), now: readAt)
            let mergedData = try encode(merged)
            let localChanged = try mergedData != encode(local)
            if localChanged {
                do throws(SyncDocumentError) {
                    try store.replace(merged)
                } catch {
                    throw .invalidDocument(detail: "local document not saved")
                }
                onLocalChange(name)
            }
            // Nothing to create while the merged document is still empty.
            let workerData = try encode(remoteDocument ?? Store.Document.empty)
            let summary = "\(name.rawValue) attempt \(attempt): \(merged.entryCount) entries, local \(localChanged ? "changed" : "unchanged")"
            guard mergedData != workerData else {
                logger.info("\(summary, privacy: .public), Worker up to date")
                setLastSyncAt(readAt, for: name)
                return readAt
            }
            let precondition: SyncClient.Precondition = remote.map { .replace($0.etag) } ?? .create
            switch try await transport.put(name, data: mergedData, precondition: precondition) {
            case .stored:
                logger.info("\(summary, privacy: .public), pushed")
                setLastSyncAt(readAt, for: name)
                return readAt
            case let .conflict(data?, etag?):
                logger.info("\(summary, privacy: .public), conflict")
                remote = (data, etag)
            case .conflict(nil, _):
                logger.info("\(summary, privacy: .public), conflict with a store that doesn't exist")
                remote = nil
            case .conflict(.some, nil):
                throw .server(status: 412)
            }
        }
        throw .conflictPersisted
    }

    private func decode<Document: SyncDocument>(_: Document.Type, from data: Data) throws(SyncError) -> Document {
        do throws(SyncDocumentError) {
            return try SyncCoding.decode(Document.self, from: data)
        } catch {
            if case let .unsupportedFormat(format) = error {
                throw .unsupportedFormat(format)
            }
            // The detail of a decoding error can contain video IDs; it stays out of status and logs.
            throw .invalidDocument(detail: "Worker document unreadable")
        }
    }

    private func encode(_ document: some SyncDocument) throws(SyncError) -> Data {
        do throws(SyncDocumentError) {
            return try SyncCoding.encode(document)
        } catch {
            throw .invalidDocument(detail: "document not encodable")
        }
    }

    private struct StoreState: Codable {
        var lastSyncAt: Date
    }

    private func loadState() -> [String: StoreState] {
        guard let data = defaults.data(forKey: Self.stateKey) else { return [:] }
        return (try? SyncCoding.decoder().decode([String: StoreState].self, from: data)) ?? [:]
    }

    private func setLastSyncAt(_ date: Date, for store: SyncStoreName) {
        var state = loadState()
        state[store.rawValue] = StoreState(lastSyncAt: date)
        guard let data = try? SyncCoding.canonical(state) else { return }
        defaults.set(data, forKey: Self.stateKey)
    }
}

private extension SyncEngine.Status {
    var isFailure: Bool {
        if case .failed = self {
            true
        } else {
            false
        }
    }
}
