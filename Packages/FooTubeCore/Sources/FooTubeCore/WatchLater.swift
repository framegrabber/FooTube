import Foundation
import os

/// Videos saved to watch later on this device (synced to the household's Worker when sync is on),
/// most recently added first, one entry per video.
///
/// Kept in `UserDefaults` as a `WatchLaterDocument` like `WatchHistory`; unreadable data counts as
/// empty. Removing leaves a removal marker that the readers hide, so another device's sync can't
/// bring the video back.
public struct WatchLaterStore: SyncableStore {
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let key = "watchLater.v2"
    private let legacyKey = "watchLater.v1"
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "storage")

    /// `now` stamps changes and the one-time migration from `watchLater.v1`.
    public init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { .now }) {
        self.defaults = defaults
        self.now = now
    }

    /// Most recently added first.
    public func items() -> [VideoSummary] {
        document().entries
            .filter { $0.removedAt == nil }
            .sorted(by: WatchLaterRecord.listOrder)
            .map(\.video)
    }

    public func contains(_ id: VideoID) -> Bool {
        document().entries.contains { $0.video.id == id && $0.removedAt == nil }
    }

    /// Adds the video at the front; an existing entry for the same ID moves to the front.
    public func add(_ video: VideoSummary) throws {
        var document = document()
        document.entries.removeAll { $0.video.id == video.id }
        // Strictly after every other entry, also when two adds fall into the same millisecond.
        let newest = document.entries.map(\.addedAt).max().map { $0 + 0.001 } ?? .distantPast
        let date = max(SyncCoding.timestamp(now()), newest)
        document.entries.append(WatchLaterRecord(video: video, addedAt: date, changedAt: date))
        try save(document)
    }

    /// Turns the entry into a removal marker.
    public func remove(_ id: VideoID) throws {
        var document = document()
        guard let index = document.entries.firstIndex(where: { $0.video.id == id && $0.removedAt == nil }) else { return }
        let date = SyncCoding.timestamp(now())
        document.entries[index].changedAt = date
        document.entries[index].removedAt = date
        try save(document)
    }

    /// Turns every entry into a removal marker.
    public func clear() {
        var document = document()
        let date = SyncCoding.timestamp(now())
        for index in document.entries.indices where document.entries[index].removedAt == nil {
            document.entries[index].changedAt = date
            document.entries[index].removedAt = date
        }
        do {
            try save(document)
        } catch {
            logger.error("Couldn't clear Watch Later: \(error.message, privacy: .public)")
        }
    }

    /// For sync: every entry including removal markers. Migrates `watchLater.v1` on first use: the
    /// n-th video gets `addedAt` n seconds before the migration, which keeps the order.
    public func document() -> WatchLaterDocument {
        defaults.syncDocument(WatchLaterDocument.self, forKey: key, migratingFrom: legacyKey, logger: logger) {
            let date = SyncCoding.timestamp(now())
            let list = defaults.data(forKey: legacyKey).flatMap { try? JSONDecoder().decode([VideoSummary].self, from: $0) } ?? []
            var seen = Set<VideoID>()
            let records = list.filter { seen.insert($0.id).inserted }.enumerated().map { index, video in
                let addedAt = date - TimeInterval(index)
                return WatchLaterRecord(video: video, addedAt: addedAt, changedAt: addedAt)
            }
            return WatchLaterDocument(entries: records)
        }
    }

    /// For sync: saves a merged document as is.
    public func replace(_ document: WatchLaterDocument) throws(SyncDocumentError) {
        try defaults.setSyncDocument(document, forKey: key)
    }

    private func save(_ document: WatchLaterDocument) throws(SyncDocumentError) {
        let entries = SyncMerge.withoutExpiredMarkers(document.entries, now: now())
        try replace(WatchLaterDocument(entries: entries.sorted(by: WatchLaterRecord.listOrder)))
    }
}
