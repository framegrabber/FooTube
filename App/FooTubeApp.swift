import FooTubeCore
import SwiftUI

@main
struct FooTubeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView(
                catalog: InnerTubeCatalog(),
                playback: PlaybackController(resolver: YouTubeKitResolver(), sponsorBlock: SponsorBlockClient()),
            )
        }
    }
}
