import FooTubeCore
import Foundation
import Observation
import os

/// Observable view of the local watch history: cards read progress, the player records it, the
/// History tab lists `recentVideos`.
@MainActor
@Observable
final class WatchHistoryModel {
    private var entries: [VideoID: WatchEntry]
    /// Played videos whose summary is known (recorded since the History tab existed), most recently
    /// played first.
    private(set) var recentVideos: [VideoSummary]

    /// Called after this model changed the store (`SyncModel` schedules a round).
    @ObservationIgnored var onLocalChange: (@MainActor () -> Void)?

    private let store: WatchHistory
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "history")

    init(store: WatchHistory) {
        self.store = store
        (entries, recentVideos) = Self.read(store)
    }

    /// Reads the store again after sync merged other devices' changes into it.
    func reload() {
        (entries, recentVideos) = Self.read(store)
    }

    private static func read(_ store: WatchHistory) -> ([VideoID: WatchEntry], [VideoSummary]) {
        let list = store.entries()
        return (Dictionary(list.map { ($0.videoID, $0) }) { newest, _ in newest }, [].appendingUnique(list.compactMap(\.video)))
    }

    /// Fraction watched 0...1, nil if never played (live streams are never tracked).
    func progress(for id: VideoID) -> Double? {
        entries[id]?.progress
    }

    func isWatched(_ id: VideoID) -> Bool {
        entries[id]?.watched ?? false
    }

    /// Where playback should continue, nil to start from the beginning.
    func resumePosition(for id: VideoID) -> Double? {
        entries[id]?.resumePosition
    }

    /// Videos with a saved position or watched mark, including ones played by ID only.
    var count: Int {
        entries.count
    }

    /// Forgets every position, watched mark and History entry.
    func clear() {
        store.clear()
        entries = [:]
        recentVideos = []
        onLocalChange?()
    }

    /// Saves the position and moves the video to the front of `recentVideos`; ignored without a finite
    /// duration (live streams). Without `video` the stored summary is kept.
    func record(_ id: VideoID, position: Double, duration: Double, reachedEnd: Bool = false, video: VideoSummary? = nil) {
        do {
            if let entry = try store.record(id, position: position, duration: duration, reachedEnd: reachedEnd, video: video) {
                entries[id] = entry
                if let summary = entry.video {
                    var recent = recentVideos.filter { $0.id != id }
                    recent.insert(summary, at: 0)
                    recentVideos = Array(recent.prefix(WatchHistory.capacity))
                }
                onLocalChange?()
            }
        } catch {
            logger.error("Couldn't save watch progress of \(id, privacy: .private(mask: .hash)): \(error.localizedDescription, privacy: .public)")
        }
    }
}
