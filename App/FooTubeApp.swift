import FooTubeCore
import SwiftUI

@main
struct FooTubeApp: App {
    private static let catalog = InnerTubeCatalog()

    @State private var playback = PlaybackController(resolver: YouTubeKitResolver(), sponsorBlock: SponsorBlockClient())
    @State private var subscriptions = SubscriptionsModel(store: SubscriptionStore())
    @State private var feed = FeedModel(service: FeedService(catalog: catalog), cache: FeedCache())

    var body: some Scene {
        WindowGroup {
            RootView(catalog: Self.catalog, playback: playback, subscriptions: subscriptions, feed: feed)
        }
    }
}
