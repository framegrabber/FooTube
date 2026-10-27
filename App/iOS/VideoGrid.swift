import FooTubeCore
import SwiftUI

/// Adaptive grid of video cards: one column on an iPhone in portrait, more as the width allows.
/// Tapping plays; touch and hold opens the video menu (`VideoMenu`). `onReachEnd` is called when the
/// last card appears, for paging.
struct VideoGrid: View {
    let videos: [VideoSummary]
    var onReachEnd: (() -> Void)?
    var onOpenChannel: ((ChannelRef) -> Void)?

    @ScaledMetric(relativeTo: .body) private var minimumWidth: CGFloat = 300

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 16, alignment: .top)], alignment: .leading, spacing: 24) {
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
        Button {
            playback.play(video)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                VideoThumbnail(video: video, progress: watchHistory.progress(for: video.id), isWatched: watchHistory.isWatched(video.id))
                    .clipShape(VideoThumbnail.shape)
                VideoText(video: video, titleLines: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(watchHistory.progressDescription(for: video.id))
        .contextMenu {
            VideoMenu(video: video, onOpenChannel: onOpenChannel)
        }
    }
}

/// A video as a list row: thumbnail beside the text, or above it at accessibility text sizes.
/// Watch Later and History list these with swipe actions.
struct VideoRow: View {
    let video: VideoSummary

    @Environment(WatchHistoryModel.self) private var watchHistory
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var thumbnailWidth: CGFloat = 150

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            VideoThumbnail(video: video, progress: watchHistory.progress(for: video.id), isWatched: watchHistory.isWatched(video.id))
                .clipShape(VideoThumbnail.shape)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : thumbnailWidth)
            VideoText(video: video, titleLines: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(watchHistory.progressDescription(for: video.id))
    }
}

/// Title and one line of details (date first: in narrow columns the end of the line is cut, and the
/// feed is sorted by date).
private struct VideoText: View {
    let video: VideoSummary
    let titleLines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(video.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(titleLines)
                .multilineTextAlignment(.leading)
            Text([video.published, video.channel?.name, video.viewCount].compactMap(\.self).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
