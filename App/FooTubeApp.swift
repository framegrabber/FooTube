import FooTubeCore
import SwiftUI

@main
struct FooTubeApp: App {
    private static let catalog = InnerTubeCatalog()

    @State private var watchHistory: WatchHistoryModel
    @State private var playback: PlaybackController
    @State private var subscriptions = SubscriptionsModel(store: SubscriptionStore())
    @State private var feed = FeedModel(service: FeedService(catalog: catalog), cache: FeedCache())
    @State private var watchLater = WatchLaterModel(store: WatchLaterStore())

    init() {
        let history = WatchHistoryModel(store: WatchHistory())
        _watchHistory = State(initialValue: history)
        _playback = State(initialValue: PlaybackController(resolver: YouTubeKitResolver(), catalog: Self.catalog, sponsorBlock: SponsorBlockClient(), history: history))
    }

    var body: some Scene {
        WindowGroup {
            RootView(catalog: Self.catalog, playback: playback, subscriptions: subscriptions, feed: feed)
                .environment(watchHistory)
                .environment(watchLater)
        }
    }
}
