import FooTubeCore
import SwiftUI

/// Tabs plus the shared full-screen player and resolve/failure banner.
struct RootView: View {
    enum TabID: Hashable {
        case subscriptions, search, play
    }

    let catalog: any Catalog
    @State var playback: PlaybackController
    @State var subscriptions: SubscriptionsModel
    @State var feed: FeedModel
    @State private var didAutoplay = false
    @State private var selectedTab: TabID = .subscriptions
    /// Bumped when the user goes up to the tab bar and comes back into the Search tab; SearchView
    /// then clears the query and results so focus lands on the search keyboard.
    @State private var searchResets = 0
    @State private var focusIsInTabBar = false
    @State private var searchContentVisited = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Subscriptions", systemImage: "person.2", value: .subscriptions) {
                SubscriptionsView(catalog: catalog)
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchView(catalog: catalog, resetToken: searchResets)
            }
            Tab("Play", systemImage: "play.rectangle", value: .play) {
                HomeView()
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
                selectedTab = .search // direct assignment: must not trigger the Search reset
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

    /// "Choose Search again" = focus goes up into the tab bar and comes back down into the Search tab.
    /// tvOS offers no API to focus a `searchable` field (`searchFocused`, `searchable(isPresented:)`
    /// are unavailable) and re-selecting the current tab does not call the selection binding, so the
    /// focus system is observed instead. Clearing the search leaves the keyboard as the only
    /// focusable content, so focus lands on it.
    private func focusMoved(_ note: Notification) {
        // Updates without a focused view (launch, scene changes) are neither tab bar nor content.
        guard let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext,
              let view = context.nextFocusedItem as? UIView else { return }
        let nowInTabBar = Self.isInTabBar(view)
        defer { focusIsInTabBar = nowInTabBar }
        guard !nowInTabBar, selectedTab == .search else { return }
        // The first time focus enters Search content (app launch, `-search` hook) is not "again".
        if focusIsInTabBar, searchContentVisited {
            searchResets += 1
        }
        searchContentVisited = true
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
