import FooTubeCore
import SwiftUI

/// Videos saved with "Add to Watch Later" (long press on a video), most recently added first.
/// Channels open in this tab's navigation stack, whose `path` the tab owner holds.
struct WatchLaterView: View {
    let catalog: any Catalog
    @Binding var path: [ChannelRef]

    @Environment(WatchLaterModel.self) private var watchLater

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 48) {
                    if let error = watchLater.lastError {
                        Text(error).foregroundStyle(.red)
                    }
                    if watchLater.items.isEmpty {
                        Text("Nothing saved yet. Press and hold a video and choose Add to Watch Later.")
                            .foregroundStyle(.secondary)
                    }
                    VideoGrid(videos: watchLater.items, onOpenChannel: { path.append($0) })
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
