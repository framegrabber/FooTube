import FooTubeCore
import Foundation
import Observation
import os

/// Observable view of the local watch history: cards read progress, the player records it.
@MainActor
@Observable
final class WatchHistoryModel {
    private var entries: [VideoID: WatchEntry]

    private let store: WatchHistory
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "history")

    init(store: WatchHistory) {
        self.store = store
        entries = Dictionary(store.entries().map { ($0.videoID, $0) }) { newest, _ in newest }
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

    /// Saves the position; ignored without a finite duration (live streams).
    func record(_ id: VideoID, position: Double, duration: Double, reachedEnd: Bool = false) {
        do {
            if let entry = try store.record(id, position: position, duration: duration, reachedEnd: reachedEnd) {
                entries[id] = entry
            }
        } catch {
            let line = "Couldn't save watch progress of \(id): \(error.localizedDescription)"
            logger.error("\(line, privacy: .public)")
        }
    }
}
