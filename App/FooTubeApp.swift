import FooTubeCore
import SwiftUI

@main
struct FooTubeApp: App {
    private static let catalog = InnerTubeCatalog()

    @State private var watchHistory: WatchHistoryModel
    @State private var playback: PlaybackController
    @State private var settings: SettingsModel
    @State private var subscriptions: SubscriptionsModel
    @State private var feed = FeedModel(service: FeedService(catalog: catalog), cache: FeedCache())
    @State private var watchLater: WatchLaterModel
    @State private var sync: SyncModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let history = WatchHistoryModel(store: WatchHistory())
        let settings = SettingsModel(store: SkipSettingsStore())
        let subscriptions = SubscriptionsModel(store: SubscriptionStore())
        let watchLater = WatchLaterModel(store: WatchLaterStore())
        let sync = SyncModel(subscriptions: subscriptions, watchLater: watchLater, history: history, settings: settings)
        let playback = PlaybackController(
            resolver: YouTubeKitResolver(),
            catalog: Self.catalog,
            sponsorBlock: SponsorBlockClient(),
            history: history,
            settings: settings,
        )
        playback.onPlayerClosed = { sync.playerClosed() }
        _watchHistory = State(initialValue: history)
        _settings = State(initialValue: settings)
        _subscriptions = State(initialValue: subscriptions)
        _watchLater = State(initialValue: watchLater)
        _sync = State(initialValue: sync)
        _playback = State(initialValue: playback)
    }

    var body: some Scene {
        WindowGroup {
            RootView(catalog: Self.catalog, playback: playback, subscriptions: subscriptions, feed: feed)
                .environment(watchHistory)
                .environment(watchLater)
                .environment(settings)
                .environment(sync)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            sync.scenePhaseChanged(to: phase)
        }
    }
}
