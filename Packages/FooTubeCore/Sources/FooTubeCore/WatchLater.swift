import Foundation

/// Videos saved to watch later on this device, most recently added first, one entry per video.
///
/// Kept in `UserDefaults` as a JSON list like `WatchHistory`; unreadable data counts as empty.
public struct WatchLaterStore {
    private let defaults: UserDefaults
    private let key = "watchLater.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Most recently added first.
    public func items() -> [VideoSummary] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([VideoSummary].self, from: data) else { return [] }
        return list
    }

    public func contains(_ id: VideoID) -> Bool {
        items().contains { $0.id == id }
    }

    /// Adds the video at the front; an existing entry for the same ID moves to the front.
    public func add(_ video: VideoSummary) throws {
        var list = items().filter { $0.id != video.id }
        list.insert(video, at: 0)
        try save(list)
    }

    public func remove(_ id: VideoID) throws {
        try save(items().filter { $0.id != id })
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }

    private func save(_ list: [VideoSummary]) throws {
        try defaults.set(JSONEncoder().encode(list), forKey: key)
    }
}
