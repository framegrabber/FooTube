import FooTubeCore
import SwiftUI

@main
struct FooTubeApp: App {
    private let catalog = InnerTubeCatalog()

    @State private var subscriptions: SubscriptionsModel = {
        do {
            return try SubscriptionsModel(store: SubscriptionStore())
        } catch {
            return SubscriptionsModel(store: nil, error: "Subscriptions unavailable: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView(
                catalog: catalog,
                playback: PlaybackController(resolver: YouTubeKitResolver(), sponsorBlock: SponsorBlockClient()),
                subscriptions: subscriptions,
                feed: FeedModel(service: FeedService(catalog: catalog), cache: FeedCache()),
            )
        }
    }
}
