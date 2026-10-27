import FooTubeCore
import SwiftUI

/// Grid of video cards (tvOS lockups). Selecting plays; long press opens a menu with "Open <channel>"
/// (when `onOpenChannel` is set) and Add to / Remove from Watch Later. `onReachEnd` is called when the
/// last card appears, for paging. Put it in a scroll view with `.scrollClipDisabled()` so focused cards
/// can lift past its edges.
struct VideoGrid: View {
    let videos: [VideoSummary]
    var onReachEnd: (() -> Void)?
    var onOpenChannel: ((ChannelRef) -> Void)?

    /// Wide gaps leave room for the focused card's lift and shadow.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 48), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 64) {
            ForEach(videos) { video in
                VideoGridCell(video: video, onOpenChannel: onOpenChannel)
                    .onAppear {
                        if video.id == videos.last?.id {
                            onReachEnd?()
                        }
                    }
            }
        }
    }
}

/// One card; reads watch history here so a progress change only redraws this card.
private struct VideoGridCell: View {
    let video: VideoSummary
    let onOpenChannel: ((ChannelRef) -> Void)?

    @Environment(PlaybackController.self) private var playback
    @Environment(WatchHistoryModel.self) private var watchHistory

    var body: some View {
        card.contextMenu {
            VideoMenu(video: video, onOpenChannel: onOpenChannel)
        } preview: {
            // An opaque preview of exactly the thumbnail; the default preview snapshots the
            // whole card (thumbnail and text) onto a platter.
            thumbnail
                .frame(width: VideoThumbnail.displaySize.width, height: VideoThumbnail.displaySize.height)
                .clipShape(VideoThumbnail.shape)
        }
    }

    /// The tvOS lockup: the borderless style lifts the thumbnail (highlight hover effect: lift,
    /// specular highlight, gimbal tilt) and moves the text below out of its way.
    private var card: some View {
        Button {
            playback.play(video)
        } label: {
            VideoCard(video: video, thumbnail: thumbnail)
        }
        .buttonStyle(.borderless)
        .buttonBorderShape(.roundedRectangle(radius: VideoThumbnail.cornerRadius))
        .accessibilityValue(watchHistory.progressDescription(for: video.id))
    }

    private var thumbnail: VideoThumbnail {
        VideoThumbnail(
            video: video,
            progress: watchHistory.progress(for: video.id),
            isWatched: watchHistory.isWatched(video.id),
        )
    }
}

/// Label of a borderless video button: the thumbnail carries the focus effect (badges and progress
/// move with it); title and details stay plain text.
struct VideoCard: View {
    let video: VideoSummary
    let thumbnail: VideoThumbnail

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            thumbnail
                .clipShape(VideoThumbnail.shape)
                .hoverEffect(.highlight)

            Text(video.title)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
            // Date first: in narrow columns the end of the line is cut, and the feed is sorted by date.
            Text([video.published, video.channel?.name, video.viewCount].compactMap(\.self).joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
