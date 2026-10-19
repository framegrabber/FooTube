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
            ScrollView {
                VStack(alignment: .leading, spacing: 48) {
                    if watchHistory.recentVideos.isEmpty {
                        Text("No history yet. Videos you play show up here, most recent first.")
                            .foregroundStyle(.secondary)
                    }
                    VideoGrid(videos: watchHistory.recentVideos, onOpenChannel: { path.append($0) })
                }
                .padding(80)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollClipDisabled() // focused lockups lift past the scroll view's edges
            .navigationDestination(for: ChannelRef.self) { channel in
                ChannelView(catalog: catalog, channel: channel)
            }
        }
    }
}
