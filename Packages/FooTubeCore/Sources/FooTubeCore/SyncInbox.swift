import Foundation

/// A video saved from a browser with the bookmarklet, waiting on the Worker (`GET /v1/inbox`) until a
/// device folds it into Watch Later (SPEC-browser-inbox → Client).
public struct InboxItem: Codable, Hashable, Sendable {
    /// Increases with every add; `DELETE /v1/inbox?through=<seq>` removes this item and older ones.
    public let seq: Int
    public let videoID: String
    public let title: String?
    public let addedAt: Date

    public init(seq: Int, videoID: String, title: String?, addedAt: Date) {
        self.seq = seq
        self.videoID = videoID
        self.title = title
        self.addedAt = addedAt
    }
}

public enum SyncInbox {
    /// Watch Later with the inbox items added. An item becomes an entry unless its video is already
    /// live, or was removed (or re-added) at or after the item's `addedAt`, i.e. on purpose after it was
    /// bookmarked. The entry's `addedAt` is the item's (orders the list); `changedAt` is `now`, the time
    /// of folding: with the item's `addedAt` the next merge would take the entry for one pruned
    /// elsewhere (changed before `lastSyncAt`, missing on the Worker) and drop it. Items with an invalid
    /// video ID are skipped. Pure: the same inputs give the same document.
    public static func fold(_ items: [InboxItem], into document: WatchLaterDocument, now: Date) -> WatchLaterDocument {
        var document = document
        for item in items {
            guard let id = VideoID(item.videoID) else { continue }
            let addedAt = min(SyncCoding.timestamp(item.addedAt), now)
            let existing = document.entries.firstIndex { $0.video.id == id }
            if let existing {
                let record = document.entries[existing]
                guard record.removedAt != nil, record.changedAt < addedAt else { continue }
                document.entries.remove(at: existing)
            }
            document.entries.append(WatchLaterRecord(video: .bare(id, title: item.title), addedAt: addedAt, changedAt: now))
        }
        document.entries.sort(by: WatchLaterRecord.listOrder)
        return document
    }
}
