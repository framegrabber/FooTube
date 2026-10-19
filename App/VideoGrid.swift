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
    @Environment(WatchLaterModel.self) private var watchLater

    var body: some View {
        card.contextMenu {
            if let channel = video.channel, let onOpenChannel {
                Button("Open \(channel.name ?? "Channel")", systemImage: "person.crop.rectangle") {
                    onOpenChannel(channel)
                }
            }
            if watchLater.contains(video.id) {
                Button("Remove from Watch Later", systemImage: "text.badge.minus") {
                    watchLater.toggle(video)
                }
            } else {
                Button("Add to Watch Later", systemImage: "text.badge.plus") {
                    watchLater.toggle(video)
                }
            }
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
            Text([video.channel?.name, video.viewCount, video.published].compactMap(\.self).joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// 16:9 thumbnail with duration badge and watch state. Not clipped: callers clip to `shape`.
struct VideoThumbnail: View {
    static let cornerRadius: CGFloat = 12
    static let shape = RoundedRectangle(cornerRadius: cornerRadius)
    /// Largest size shown (the long-press preview); grid cards are smaller, so one decode serves both.
    static let displaySize = CGSize(width: 640, height: 360)

    let video: VideoSummary
    /// Fraction watched 0...1, nil if never played.
    let progress: Double?
    let isWatched: Bool

    var body: some View {
        RemoteImage(url: video.thumbnail, size: Self.displaySize)
            .opacity(isWatched ? 0.6 : 1)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                if isWatched {
                    Label("Watched", systemImage: "checkmark")
                        .font(.caption2.bold())
                        .badgeStyle()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 0) {
                    if let duration = video.duration {
                        Text(duration)
                            .font(.caption2.monospacedDigit())
                            .badgeStyle()
                    }
                    if let fraction = isWatched ? 1 : progress {
                        ProgressStripe(fraction: fraction)
                    }
                }
            }
    }
}

/// Thin red bar along the thumbnail bottom, like YouTube's resume indicator.
private struct ProgressStripe: View {
    let fraction: Double

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.4))
            .frame(height: 6)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.red)
                    .scaleEffect(x: min(max(fraction, 0), 1), anchor: .leading)
            }
    }
}

private extension View {
    /// White text on a dark plate in every appearance (the default foreground turns black in light mode).
    func badgeStyle() -> some View {
        foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.75), in: .rect(cornerRadius: 6))
            .padding(8)
    }
}
