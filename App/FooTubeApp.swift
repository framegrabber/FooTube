import FooTubeCore
import SwiftUI

@main
struct FooTubeApp: App {
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
                catalog: InnerTubeCatalog(),
                playback: PlaybackController(resolver: YouTubeKitResolver(), sponsorBlock: SponsorBlockClient()),
                subscriptions: subscriptions,
            )
        }
    }
}
