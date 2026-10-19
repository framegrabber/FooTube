import FooTubeCore
import SwiftUI

/// Tabs plus the shared full-screen player and resolve/failure banner.
struct RootView: View {
    enum TabID: Hashable {
        case subscriptions, search, watchLater, history
    }

    let catalog: any Catalog
    @State var playback: PlaybackController
    @State var subscriptions: SubscriptionsModel
    @State var feed: FeedModel
    @State private var didAutoplay = false
    @State private var selectedTab: TabID = .subscriptions
    /// Navigation path (pushed channel pages) of each tab.
    @State private var paths: [TabID: [ChannelRef]] = [:]
    @State private var focusIsInTabBar = false
    /// Tabs whose content had focus before; the first visit (launch, tab switch) is not a "return".
    @State private var visitedTabs: Set<TabID> = []

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Subscriptions", systemImage: "person.2", value: .subscriptions) {
                SubscriptionsView(catalog: catalog, path: path(.subscriptions))
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchView(catalog: catalog, path: path(.search))
            }
            Tab("Watch Later", systemImage: "clock", value: .watchLater) {
                WatchLaterView(catalog: catalog, path: path(.watchLater))
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: .history) {
                HistoryView(catalog: catalog, path: path(.history))
            }
        }
        .environment(playback)
        .environment(subscriptions)
        .environment(feed)
        .onReceive(NotificationCenter.default.publisher(for: UIFocusSystem.didUpdateNotification)) { note in
            focusMoved(note)
        }
        .overlay(alignment: .bottom) {
            StatusBanner(status: playback.status)
        }
        .fullScreenCover(item: $playback.session) { session in
            PlayerView(session: session)
                .ignoresSafeArea()
                .overlay(alignment: .topLeading) {
                    #if DEBUG
                        DiagnosticsOverlay(session: session)
                    #endif
                }
                .overlay(alignment: .bottomLeading) {
                    if let notice = session.notice {
                        Text(notice)
                            .font(.callout)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.black.opacity(0.7), in: .capsule)
                            .padding(60)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .onExitCommand { playback.session = nil }
        }
        .task {
            // Debug/test hooks (simctl/devicectl launch arguments), once per launch:
            // `-play <id or URL>`, `-subscribe <channelID>` (comma-separated for several).
            guard !didAutoplay else { return }
            didAutoplay = true
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

    /// Returning from the tab bar into a tab = "choose it again": the tab goes back to its root
    /// (Apple's tab bar convention). Search keeps its query and results, so overshooting from the
    /// search keyboard to the tab bar loses nothing. tvOS calls no selection binding when the current
    /// tab is chosen again, so the focus system is observed instead.
    private func focusMoved(_ note: Notification) {
        // Updates without a focused item (launch, scene changes) are neither tab bar nor content.
        // SwiftUI buttons are focus items but not UIViews; only the tab bar is UIKit.
        guard let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext,
              let item = context.nextFocusedItem else { return }
        let nowInTabBar = (item as? UIView).map(Self.isInTabBar) ?? false
        defer { focusIsInTabBar = nowInTabBar }
        guard !nowInTabBar else { return }
        if focusIsInTabBar, visitedTabs.contains(selectedTab) {
            paths[selectedTab] = []
        }
        visitedTabs.insert(selectedTab)
    }

    private func path(_ tab: TabID) -> Binding<[ChannelRef]> {
        Binding(get: { paths[tab] ?? [] }, set: { paths[tab] = $0 })
    }

    private static func isInTabBar(_ view: UIView) -> Bool {
        sequence(first: view, next: \.superview).contains { $0 is UITabBar }
    }
}

private struct StatusBanner: View {
    let status: PlaybackController.Status

    var body: some View {
        Group {
            switch status {
            case .idle:
                EmptyView()
            case let .resolving(id):
                HStack(spacing: 24) {
                    ProgressView()
                    Text("Loading \(id.rawValue)…")
                }
                .padding(24)
                .background(.regularMaterial, in: .capsule)
            case let .failed(message):
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .background(.regularMaterial, in: .rect(cornerRadius: 20))
            }
        }
        .padding(.bottom, 40)
        .allowsHitTesting(false)
    }
}
