import FooTubeCore
import Observation

/// Subscriptions feed: shows the cached snapshot instantly, then refreshes from YouTube.
@MainActor
@Observable
final class FeedModel {
    private(set) var snapshot: FeedSnapshot?
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    private let service: FeedService
    private let cache: FeedCache

    init(service: FeedService, cache: FeedCache) {
        self.service = service
        self.cache = cache
        snapshot = cache.load()
    }

    func refresh(_ subscriptions: [Subscription]) async {
        guard !isRefreshing else { return }
        guard !subscriptions.isEmpty else {
            snapshot = nil
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        guard let fresh = await service.refresh(subscriptions.map(\.channel)) else {
            lastError = "Couldn't refresh the feed."
            return
        }
        snapshot = fresh
        lastError = nil
        try? cache.save(fresh)
    }
}
