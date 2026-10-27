import FooTubeCore
import SwiftUI

/// iPhone and iPad: the tabs, a tab bar on iPhone that iPad can turn into a sidebar.
struct RootView: View {
    enum TabID: Hashable {
        case subscriptions, search, watchLater, history, settings
    }

    let catalog: any Catalog
    @State var playback: PlaybackController
    @State var subscriptions: SubscriptionsModel
    @State var feed: FeedModel
    @State private var selectedTab: TabID = .subscriptions

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Subscriptions", systemImage: "person.2", value: .subscriptions) {
                NavigationStack {
                    Color.clear.navigationTitle("Subscriptions")
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                NavigationStack {
                    Color.clear.navigationTitle("Search")
                }
            }
            Tab("Watch Later", systemImage: "clock", value: .watchLater) {
                NavigationStack {
                    Color.clear.navigationTitle("Watch Later")
                }
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: .history) {
                NavigationStack {
                    Color.clear.navigationTitle("History")
                }
            }
            Tab("Settings", systemImage: "gear", value: .settings) {
                NavigationStack {
                    Color.clear.navigationTitle("Settings")
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(playback)
        .environment(subscriptions)
        .environment(feed)
    }
}
