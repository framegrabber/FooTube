import Foundation

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

    public init(videoID: VideoID, position: Double, duration: Double, updatedAt: Date, watched: Bool) {
        self.videoID = videoID
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
        self.watched = watched
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

/// Watch progress stored only on this device, newest first, at most `capacity` videos.
///
/// Kept in `UserDefaults` as a JSON list like `SubscriptionStore`: on tvOS that is the persistent
/// local store; files in Application Support or Caches can be purged while the app is not running.
/// 500 entries are about 55 KB.
public struct WatchHistory {
    public static let capacity = 500
    /// Fraction of the duration at which a video counts as watched.
    public static let watchedFraction = 0.9
    public static let minimumResumePosition = 10.0
    public static let endMargin = 30.0

    private let defaults: UserDefaults
    private let key = "watchHistory.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Newest first.
    public func entries() -> [WatchEntry] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([WatchEntry].self, from: data) else { return [] }
        return list
    }

    public func entry(for id: VideoID) -> WatchEntry? {
        entries().first { $0.videoID == id }
    }

    public func resumePosition(for id: VideoID) -> Double? {
        entry(for: id)?.resumePosition
    }

    /// Saves the playback position and moves the video to the front of the history, dropping the
    /// oldest entries beyond `capacity`. `reachedEnd` marks the video watched regardless of position.
    /// Returns nil (and stores nothing) without a finite, positive duration, e.g. for live streams.
    @discardableResult
    public func record(
        _ id: VideoID,
        position: Double,
        duration: Double,
        reachedEnd: Bool = false,
        at date: Date = .now,
    ) throws -> WatchEntry? {
        guard duration.isFinite, duration > 0, position.isFinite else { return nil }
        let clamped = reachedEnd ? duration : min(max(position, 0), duration)
        var list = entries()
        let previous = list.firstIndex { $0.videoID == id }.map { list.remove(at: $0) }
        let entry = WatchEntry(
            videoID: id,
            position: clamped,
            duration: duration,
            updatedAt: date,
            watched: (previous?.watched ?? false) || reachedEnd || clamped >= duration * Self.watchedFraction,
        )
        list.insert(entry, at: 0)
        try defaults.set(JSONEncoder().encode(Array(list.prefix(Self.capacity))), forKey: key)
        return entry
    }
}
