import Foundation
import os

/// How far one video was watched.
public struct WatchEntry: Codable, Hashable, Sendable {
    public let videoID: VideoID
    /// Seconds into the video.
    public let position: Double
    /// Seconds.
    public let duration: Double
    public let updatedAt: Date
    /// Reached 90 % or the end at some point; stays set when re-watching.
    public let watched: Bool
    /// Title, channel and thumbnail for listing the history; nil for entries stored before
    /// summaries were recorded.
    public let video: VideoSummary?

    public init(
        videoID: VideoID,
        position: Double,
        duration: Double,
        updatedAt: Date,
        watched: Bool,
        video: VideoSummary? = nil,
    ) {
        self.videoID = videoID
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
        self.watched = watched
        self.video = video
    }

    /// Fraction watched, 0...1; 1 once watched.
    public var progress: Double {
        guard !watched else { return 1 }
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// Where playback should continue, or nil to start from the beginning: positions in the
    /// first 10 s or the last 30 s are not worth resuming.
    public var resumePosition: Double? {
        position > WatchHistory.minimumResumePosition && position < duration - WatchHistory.endMargin ? position : nil
    }
}

/// Watch progress kept on this device (synced to the household's Worker when sync is on), newest
/// first, at most `capacity` videos.
///
/// Kept in `UserDefaults` as a `HistoryDocument` like `SubscriptionStore`: on tvOS that is the
/// persistent local store; files in Application Support or Caches can be purged while the app is not
/// running. 500 entries are about 55 KB.
public struct WatchHistory: SyncableStore {
    public static let capacity = 500
    /// Fraction of the duration at which a video counts as watched.
    public static let watchedFraction = 0.9
    public static let minimumResumePosition = 10.0
    public static let endMargin = 30.0

    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let key = "watchHistory.v2"
    private let legacyKey = "watchHistory.v1"
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "storage")

    /// `now` stamps `clear()`; `record` takes its date as a parameter.
    public init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { .now }) {
        self.defaults = defaults
        self.now = now
    }

    /// Newest first.
    public func entries() -> [WatchEntry] {
        document().entries
    }

    public func entry(for id: VideoID) -> WatchEntry? {
        entries().first { $0.videoID == id }
    }

    public func resumePosition(for id: VideoID) -> Double? {
        entry(for: id)?.resumePosition
    }

    /// Saves the playback position and moves the video to the front of the history, dropping the
    /// oldest entries beyond `capacity`. `reachedEnd` marks the video watched regardless of position.
    /// `video` replaces the stored summary; nil keeps the previous one.
    /// Returns nil (and stores nothing) without a finite, positive duration, e.g. for live streams.
    @discardableResult
    public func record(
        _ id: VideoID,
        position: Double,
        duration: Double,
        reachedEnd: Bool = false,
        at date: Date = .now,
        video: VideoSummary? = nil,
    ) throws -> WatchEntry? {
        guard duration.isFinite, duration > 0, position.isFinite else { return nil }
        let clamped = reachedEnd ? duration : min(max(position, 0), duration)
        var document = document()
        let previous = document.entries.firstIndex { $0.videoID == id }.map { document.entries.remove(at: $0) }
        let entry = WatchEntry(
            videoID: id,
            position: clamped,
            duration: duration,
            updatedAt: SyncCoding.timestamp(date),
            watched: (previous?.watched ?? false) || reachedEnd || clamped >= duration * Self.watchedFraction,
            video: video ?? previous?.video,
        )
        document.entries.insert(entry, at: 0)
        document.entries = Array(document.entries.prefix(Self.capacity))
        try replace(document)
        return entry
    }

    /// Forgets every entry: positions, watched marks and summaries; with sync on, on every device
    /// (`clearedAt`).
    public func clear() {
        do {
            try replace(HistoryDocument(clearedAt: SyncCoding.timestamp(now()), entries: []))
        } catch {
            logger.error("Couldn't clear watch history: \(error.message, privacy: .public)")
        }
    }

    /// For sync. Migrates `watchHistory.v1` on first use; entries keep their `updatedAt`.
    public func document() -> HistoryDocument {
        defaults.syncDocument(HistoryDocument.self, forKey: key, migratingFrom: legacyKey, logger: logger) {
            let list = defaults.data(forKey: legacyKey).flatMap { try? JSONDecoder().decode([WatchEntry].self, from: $0) } ?? []
            return HistoryDocument(entries: Array(list.prefix(Self.capacity)))
        }
    }

    /// For sync: saves a merged document as is.
    public func replace(_ document: HistoryDocument) throws(SyncDocumentError) {
        try defaults.setSyncDocument(document, forKey: key)
    }
}
