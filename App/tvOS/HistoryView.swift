import FooTubeCore
import SwiftUI

/// Watched and partly watched videos, most recently played first, with their progress bars.
/// Channels open in this tab's navigation stack, whose `path` the tab owner holds.
struct HistoryView: View {
    let catalog: any Catalog
    @Binding var path: [ChannelRef]

    @Environment(WatchHistoryModel.self) private var watchHistory

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if watchHistory.recentVideos.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Videos you play appear here, most recent first, so you can pick up where you left off."),
                    )
                } else {
                    ScrollView {
                        VideoGrid(videos: watchHistory.recentVideos, onOpenChannel: { path.append($0) })
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
}
