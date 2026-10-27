import FooTubeCore
import SwiftUI

/// Watched and partly watched videos, most recently played first, with their progress bars. Swipe
/// to add to or remove from Watch Later.
struct HistoryView: View {
    let catalog: any Catalog

    @Environment(WatchHistoryModel.self) private var watchHistory
    @Environment(WatchLaterModel.self) private var watchLater
    @Environment(PlaybackController.self) private var playback
    @State private var path: [ChannelRef] = []

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
                    List(watchHistory.recentVideos) { video in
                        Button {
                            playback.play(video)
                        } label: {
                            VideoRow(video: video)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if watchLater.contains(video.id) {
                                Button("Remove from Watch Later", systemImage: "text.badge.minus") {
                                    watchLater.toggle(video)
                                }
                            } else {
                                Button("Add to Watch Later", systemImage: "text.badge.plus") {
                                    watchLater.toggle(video)
                                }
                                .tint(.indigo)
                            }
                        }
                        .contextMenu {
                            VideoMenu(video: video, onOpenChannel: { path.append($0) })
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: ChannelRef.self) { channel in
                ChannelView(catalog: catalog, channel: channel)
            }
        }
    }
}
