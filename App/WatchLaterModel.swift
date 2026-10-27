import FooTubeCore
import Foundation
import Observation

/// Observable view of the local Watch Later list: video card menus toggle it, the Watch Later tab lists it.
@MainActor
@Observable
final class WatchLaterModel {
    /// Most recently added first.
    private(set) var items: [VideoSummary]
    private(set) var lastError: String?

    /// Called after this model changed the store (`SyncModel` schedules a round).
    @ObservationIgnored var onLocalChange: (@MainActor () -> Void)?

    private let store: WatchLaterStore

    init(store: WatchLaterStore) {
        self.store = store
        items = store.items()
    }

    /// Reads the store again after sync merged other devices' changes into it.
    func reload() {
        items = store.items()
    }

    func contains(_ id: VideoID) -> Bool {
        items.contains { $0.id == id }
    }

    /// Adds the video at the front unless it's already saved (`footube://watch-later` links).
    func add(_ video: VideoSummary) {
        guard !contains(video.id) else { return }
        toggle(video)
    }

    /// Adds the video at the front, or removes it if already saved.
    func toggle(_ video: VideoSummary) {
        do {
            if contains(video.id) {
                try store.remove(video.id)
            } else {
                try store.add(video)
            }
            items = store.items()
            lastError = nil
            onLocalChange?()
        } catch {
            lastError = String(localized: "Couldn't save Watch Later: \(error.localizedDescription)")
        }
    }

    func clear() {
        store.clear()
        items = []
        lastError = nil
        onLocalChange?()
    }
}
