import FooTubeCore
import SwiftUI

/// Videos saved with Add to Watch Later, most recently added first; swipe to remove. With sync on,
/// pull to refresh syncs Watch Later right away, picking up videos added from a browser or the
/// "Add to FooTube" shortcut.
struct WatchLaterView: View {
    let catalog: any Catalog

    @Environment(WatchLaterModel.self) private var watchLater
    @Environment(SyncModel.self) private var sync
    @Environment(PlaybackController.self) private var playback
    @State private var path: [ChannelRef] = []
    @State private var refreshFailed = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Watch Later")
                .navigationDestination(for: ChannelRef.self) { channel in
                    ChannelView(catalog: catalog, channel: channel)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if sync.isConfigured {
            items.refreshable { await refresh() }
        } else {
            items
        }
    }

    @ViewBuilder
    private var items: some View {
        if watchLater.items.isEmpty {
            // In a scroll view so pull to refresh also works while the list is empty.
            ScrollView {
                ContentUnavailableView {
                    Label("Nothing Saved", systemImage: "clock")
                } description: {
                    Text("Touch and hold a video and choose Add to Watch Later.")
                } actions: {
                    if let error = watchLater.lastError {
                        ErrorMessage(message: error)
                    }
                    if refreshFailed {
                        ErrorMessage(message: String(localized: "Couldn't reach the sync server. Try again later."))
                    }
                }
                .containerRelativeFrame(.vertical)
            }
        } else {
            rows
        }
    }

    private var rows: some View {
        List {
            if let error = watchLater.lastError {
                ErrorMessage(message: error)
            }
            if refreshFailed {
                ErrorMessage(message: String(localized: "Couldn't reach the sync server. Try again later."))
            }
            ForEach(watchLater.items) { video in
                Button {
                    playback.play(video)
                } label: {
                    VideoRow(video: video)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        watchLater.toggle(video)
                    }
                }
                .contextMenu {
                    VideoMenu(video: video, onOpenChannel: { path.append($0) })
                }
            }
        }
        .listStyle(.plain)
    }

    private func refresh() async {
        refreshFailed = await !(sync.refresh(.watchLater))
    }
}
