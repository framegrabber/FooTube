import FooTubeCore
import SwiftUI

@main
struct FooTubeApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView(resolver: YouTubeKitResolver())
        }
    }
}
