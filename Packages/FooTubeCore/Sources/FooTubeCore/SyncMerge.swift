import Foundation

/// Constants and shared steps of the merge rules (SPEC-sync-client → Merge rules). The rules are the
/// `merge(_:_:lastSyncAt:now:)` functions below: free of I/O and of the clock, and deterministic, so
/// every device computes the same document from the same two inputs.
public enum SyncMerge {
    /// Removal markers older than this are dropped.
    public static let markerLifetime: TimeInterval = 90 * 24 * 60 * 60
    /// Timestamps further than this in the future count as `now`.
    public static let futureTolerance: TimeInterval = 24 * 60 * 60

    static func clamp(_ date: Date, now: Date) -> Date {
        date > now + futureTolerance ? now : date
    }

    /// Union by key with the later `changedAt` winning (equal: the removal, then the greater canonical
    /// JSON), live local entries pruned elsewhere dropped, old markers dropped.
    static func mergeMarked<Record: MarkedRecord>(
        _ local: [Record],
        _ remote: [Record]?,
        lastSyncAt: Date?,
        now: Date,
    ) -> [Record] {
        let remote = remote?.map { $0.clamped(now: now) }
        let remoteKeys = Set(remote?.map(\.key) ?? [])
        var merged: [Record.Key: Record] = [:]
        for record in local.map({ $0.clamped(now: now) }) {
            let prunedElsewhere = remote != nil && record.removedAt == nil && !remoteKeys.contains(record.key)
                && lastSyncAt.map { record.changedAt <= $0 } == true
            guard !prunedElsewhere else { continue }
            merged[record.key] = merged[record.key].map { winner($0, record) } ?? record
        }
        for record in remote ?? [] {
            merged[record.key] = merged[record.key].map { winner($0, record) } ?? record
        }
        let cutoff = now - markerLifetime
        return merged.values.filter { record in record.removedAt.map { $0 >= cutoff } ?? true }
    }

    private static func winner<Record: MarkedRecord>(_ first: Record, _ second: Record) -> Record {
        if first.changedAt != second.changedAt {
            return first.changedAt > second.changedAt ? first : second
        }
        if (first.removedAt == nil) != (second.removedAt == nil) {
            return first.removedAt != nil ? first : second
        }
        return canonicallyGreater(first, second)
    }

    static func canonicallyGreater<Value: Encodable>(_ first: Value, _ second: Value) -> Value {
        let firstBytes = (try? SyncCoding.canonical(first)) ?? Data()
        let secondBytes = (try? SyncCoding.canonical(second)) ?? Data()
        return firstBytes.lexicographicallyPrecedes(secondBytes) ? second : first
    }

    static func mergeEntries(_ first: WatchEntry, _ second: WatchEntry) -> WatchEntry {
        let winner: WatchEntry = if first.updatedAt != second.updatedAt {
            first.updatedAt > second.updatedAt ? first : second
        } else if first.position != second.position {
            first.position > second.position ? first : second
        } else {
            canonicallyGreater(first, second)
        }
        let other = winner == first ? second : first
        return WatchEntry(
            videoID: winner.videoID,
            position: winner.position,
            duration: winner.duration,
            updatedAt: winner.updatedAt,
            watched: first.watched || second.watched,
            video: winner.video ?? other.video,
        )
    }
}

/// An entry that removal turns into a marker instead of deleting it.
protocol MarkedRecord: Encodable {
    associatedtype Key: Hashable
    var key: Key { get }
    var changedAt: Date { get }
    var removedAt: Date? { get }
    /// Future timestamps (`SyncMerge.futureTolerance`) replaced by `now`.
    func clamped(now: Date) -> Self
}

extension SubscriptionRecord: MarkedRecord {
    var key: String {
        id
    }

    func clamped(now: Date) -> SubscriptionRecord {
        var record = self
        record.changedAt = SyncMerge.clamp(changedAt, now: now)
        record.removedAt = removedAt.map { SyncMerge.clamp($0, now: now) }
        return record
    }
}

extension WatchLaterRecord: MarkedRecord {
    var key: VideoID {
        video.id
    }

    func clamped(now: Date) -> WatchLaterRecord {
        var record = self
        record.addedAt = SyncMerge.clamp(addedAt, now: now)
        record.changedAt = SyncMerge.clamp(changedAt, now: now)
        record.removedAt = removedAt.map { SyncMerge.clamp($0, now: now) }
        return record
    }
}

/// Subscriptions: union by `id`; see `SyncMerge.mergeMarked`. Entries ordered by `id`.
public func merge(
    _ local: SubscriptionsDocument,
    _ remote: SubscriptionsDocument?,
    lastSyncAt: Date?,
    now: Date,
) -> SubscriptionsDocument {
    let entries = SyncMerge.mergeMarked(local.entries, remote?.entries, lastSyncAt: lastSyncAt, now: now)
    return SubscriptionsDocument(entries: entries.sorted { $0.id < $1.id })
}

/// Watch Later: union by `video.id`; see `SyncMerge.mergeMarked`. Entries ordered newest `addedAt`
/// first.
public func merge(
    _ local: WatchLaterDocument,
    _ remote: WatchLaterDocument?,
    lastSyncAt: Date?,
    now: Date,
) -> WatchLaterDocument {
    let entries = SyncMerge.mergeMarked(local.entries, remote?.entries, lastSyncAt: lastSyncAt, now: now)
    return WatchLaterDocument(entries: entries.sorted(by: WatchLaterRecord.listOrder))
}

/// History: per video the later `updatedAt` wins (equal: the greater position), `watched` if either
/// side has it, the other side's summary if the winner has none; the later `clearedAt` drops entries
/// updated at or before it; newest first, at most `WatchHistory.capacity`. `lastSyncAt` plays no role.
public func merge(
    _ local: HistoryDocument,
    _ remote: HistoryDocument?,
    lastSyncAt _: Date?,
    now: Date,
) -> HistoryDocument {
    let clearedAt = [local.clearedAt, remote?.clearedAt].compactMap { $0.map { SyncMerge.clamp($0, now: now) } }.max()
    var merged: [VideoID: WatchEntry] = [:]
    for entry in local.entries + (remote?.entries ?? []) {
        let clamped = entry.updatedAt > now + SyncMerge.futureTolerance
            ? WatchEntry(
                videoID: entry.videoID,
                position: entry.position,
                duration: entry.duration,
                updatedAt: now,
                watched: entry.watched,
                video: entry.video,
            )
            : entry
        merged[entry.videoID] = merged[entry.videoID].map { SyncMerge.mergeEntries($0, clamped) } ?? clamped
    }
    let entries = merged.values
        .filter { entry in clearedAt.map { entry.updatedAt > $0 } ?? true }
        .sorted { $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.videoID.rawValue < $1.videoID.rawValue }
    return HistoryDocument(clearedAt: clearedAt, entries: Array(entries.prefix(WatchHistory.capacity)))
}

/// SponsorBlock settings: the whole document with the later `changedAt` wins; one without
/// `changedAt` (never changed) loses to any other; equal: the greater canonical JSON.
/// `lastSyncAt` plays no role.
public func merge(
    _ local: SkipSettingsDocument,
    _ remote: SkipSettingsDocument?,
    lastSyncAt _: Date?,
    now: Date,
) -> SkipSettingsDocument {
    var local = local
    local.changedAt = local.changedAt.map { SyncMerge.clamp($0, now: now) }
    guard var remote else { return local }
    remote.changedAt = remote.changedAt.map { SyncMerge.clamp($0, now: now) }
    switch (local.changedAt, remote.changedAt) {
    case let (localDate?, remoteDate?) where localDate != remoteDate:
        return localDate > remoteDate ? local : remote
    case (nil, .some):
        return remote
    case (.some, nil):
        return local
    default:
        return SyncMerge.canonicallyGreater(local, remote)
    }
}

extension WatchLaterRecord {
    /// Newest `addedAt` first, then by video ID.
    static func listOrder(_ first: WatchLaterRecord, _ second: WatchLaterRecord) -> Bool {
        first.addedAt != second.addedAt ? first.addedAt > second.addedAt : first.video.id.rawValue < second.video.id.rawValue
    }
}

public extension SubscriptionsDocument {
    func merged(with remote: SubscriptionsDocument?, lastSyncAt: Date?, now: Date) -> SubscriptionsDocument {
        merge(self, remote, lastSyncAt: lastSyncAt, now: now)
    }
}

public extension WatchLaterDocument {
    func merged(with remote: WatchLaterDocument?, lastSyncAt: Date?, now: Date) -> WatchLaterDocument {
        merge(self, remote, lastSyncAt: lastSyncAt, now: now)
    }
}

public extension HistoryDocument {
    func merged(with remote: HistoryDocument?, lastSyncAt: Date?, now: Date) -> HistoryDocument {
        merge(self, remote, lastSyncAt: lastSyncAt, now: now)
    }
}

public extension SkipSettingsDocument {
    func merged(with remote: SkipSettingsDocument?, lastSyncAt: Date?, now: Date) -> SkipSettingsDocument {
        merge(self, remote, lastSyncAt: lastSyncAt, now: now)
    }
}
