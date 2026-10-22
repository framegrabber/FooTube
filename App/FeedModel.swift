import FooTubeCore
import Foundation
import Observation

/// Subscriptions feed: shows the cached snapshot instantly, then refreshes from YouTube.
@MainActor
@Observable
final class FeedModel {
    /// Automatic refreshes (tab appear) are skipped when the feed is newer than this.
    static let freshness: Duration = .seconds(600)

    private(set) var snapshot: FeedSnapshot?
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    private let service: FeedService
    private let cache: FeedCache
    /// Channel IDs the current snapshot was built from.
    private var snapshotChannels: [String]?
    /// Latest subscriptions requested while a refresh was running.
    private var queued: [Subscription]?

    init(service: FeedService, cache: FeedCache) {
        self.service = service
        self.cache = cache
        snapshot = cache.load()
    }

    /// Refreshes unless the snapshot already covers these channels and is fresh. `force` ignores
    /// freshness (Refresh button). A request arriving mid-refresh runs once the current one ends.
    func refresh(_ subscriptions: [Subscription], force: Bool = false) async {
        let ids = subscriptions.map(\.id)
        if !force, ids == snapshotChannels, let fetchedAt = snapshot?.fetchedAt,
           Date.now.timeIntervalSince(fetchedAt) < Double(Self.freshness.components.seconds)
        {
            return
        }
        guard !isRefreshing else {
            queued = subscriptions
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        var next: [Subscription]? = subscriptions
        while let current = next {
            queued = nil
            if current.isEmpty {
                snapshot = nil
                snapshotChannels = []
            } else if let fresh = await service.refresh(current.map(\.channel), previous: snapshot) {
                snapshot = fresh
                snapshotChannels = current.map(\.id)
                lastError = nil
                try? cache.save(fresh)
            } else {
                lastError = String(localized: "Couldn't refresh the feed. Check the connection and choose Refresh.")
            }
            next = queued.flatMap { $0.map(\.id) == snapshotChannels ? nil : $0 }
        }
    }
}
