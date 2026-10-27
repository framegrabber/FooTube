import FooTubeCore
import SwiftUI

/// iPhone and iPad: the tabs (a tab bar on iPhone that iPad can turn into a sidebar), the status of a
/// video being loaded, and the full-screen player.
struct RootView: View {
    enum TabID: Hashable {
        case subscriptions, search, watchLater, history, settings
    }

    let catalog: any Catalog
    @State var playback: PlaybackController
    @State var subscriptions: SubscriptionsModel
    @State var feed: FeedModel
    @State private var selectedTab: TabID = .subscriptions
    @State private var didApplyLaunchArguments = false
    @Environment(WatchLaterModel.self) private var watchLater

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Subscriptions", systemImage: "person.2", value: .subscriptions) {
                SubscriptionsView(catalog: catalog, onSearch: { selectedTab = .search })
            }
            Tab("Watch Later", systemImage: "clock", value: .watchLater) {
                WatchLaterView(catalog: catalog)
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: .history) {
                HistoryView(catalog: catalog)
            }
            Tab("Settings", systemImage: "gear", value: .settings) {
                SettingsView()
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchView(catalog: catalog)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(playback)
        .environment(subscriptions)
        .environment(feed)
        .overlay(alignment: .top) {
            StatusBanner(status: playback.status)
        }
        .background {
            PlayerHost(playback: playback, session: playback.session)
        }
        .onOpenURL { url in
            switch AppLink(url) {
            case let .play(id):
                playback.play(id)
            case let .watchLater(id, title):
                watchLater.add(.bare(id, title: title))
                selectedTab = .watchLater
            case nil:
                playback.fail(String(localized: "FooTube can't open this link."))
            }
        }
        .task {
            // Debug/test hooks (simctl/devicectl launch arguments), once per launch:
            // `-play <id or URL>`, `-subscribe <channelID>` (comma-separated for several).
            guard !didApplyLaunchArguments else { return }
            didApplyLaunchArguments = true
            let defaults = UserDefaults.standard
            if defaults.string(forKey: "search") != nil || defaults.string(forKey: "channel") != nil {
                selectedTab = .search
            }
            for id in defaults.string(forKey: "subscribe")?.split(separator: ",") ?? [] where !subscriptions.isSubscribed(String(id)) {
                if let page = try? await catalog.channel(String(id)) {
                    subscriptions.toggle(page.channel, avatar: page.avatar)
                }
            }
            if let value = defaults.string(forKey: "play"), let id = VideoID(parsing: value) {
                playback.play(id)
            }
        }
    }
}
