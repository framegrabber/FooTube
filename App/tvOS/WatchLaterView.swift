import FooTubeCore
import SwiftUI

/// Videos saved with "Add to Watch Later" (long press on a video), most recently added first.
/// Channels open in this tab's navigation stack, whose `path` the tab owner holds. With sync on, a
/// Refresh button syncs Watch Later right away, picking up videos bookmarked in a browser.
struct WatchLaterView: View {
    let catalog: any Catalog
    @Binding var path: [ChannelRef]

    @Environment(WatchLaterModel.self) private var watchLater
    @Environment(SyncModel.self) private var sync
    @State private var isRefreshing = false
    @State private var refreshFailed = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if watchLater.items.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing Saved", systemImage: "clock")
                    } description: {
                        Text("Press and hold a video and choose Add to Watch Later.")
                    } actions: {
                        if let error = watchLater.lastError {
                            ErrorMessage(message: error)
                        }
                        refreshControls
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 48) {
                            if let error = watchLater.lastError {
                                ErrorMessage(message: error)
                            }
                            refreshControls
                            VideoGrid(videos: watchLater.items, onOpenChannel: { path.append($0) })
                        }
                        .padding(80)
                    }
                    .scrollClipDisabled() // focused lockups lift past the scroll view's edges
                }
            }
            .navigationDestination(for: ChannelRef.self) { channel in
                ChannelView(catalog: catalog, channel: channel)
            }
        }
    }

    @ViewBuilder
    private var refreshControls: some View {
        if sync.isConfigured {
            HStack(spacing: 40) {
                Button {
                    Task { await refresh() }
                } label: {
                    Label(isRefreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
                if refreshFailed {
                    ErrorMessage(message: String(localized: "Couldn't reach the sync server. Try again later."))
                }
            }
        }
    }

    private func refresh() async {
        isRefreshing = true
        refreshFailed = await !(sync.refresh(.watchLater))
        isRefreshing = false
    }
}
