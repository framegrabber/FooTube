import FooTubeCore
import SwiftUI

/// Grid of video cards. Selecting plays; long press opens a menu with "Open <channel>"
/// when `onOpenChannel` is set. `onReachEnd` is called when the last card appears, for paging.
struct VideoGrid: View {
    let videos: [VideoSummary]
    var onReachEnd: (() -> Void)?
    var onOpenChannel: ((ChannelRef) -> Void)?

    /// Wide gaps leave room for the focused card's scale, ring and shadow.
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
        if let channel = video.channel, let onOpenChannel {
            card.contextMenu {
                Button("Open \(channel.name ?? "Channel")", systemImage: "person.crop.rectangle") {
                    onOpenChannel(channel)
                }
            } preview: {
                // An opaque preview of exactly the thumbnail; the default preview snapshots the
                // whole card (thumbnail, text, focus effect) onto a white platter.
                thumbnail
                    .frame(width: 640, height: 360)
                    .clipShape(VideoThumbnail.shape)
            }
        } else {
            card
        }
    }

    private var card: some View {
        Button {
            playback.play(video.id)
        } label: {
            VideoCard(video: video, thumbnail: thumbnail)
        }
        .buttonStyle(CardButtonStyle())
    }

    private var thumbnail: VideoThumbnail {
        VideoThumbnail(
            video: video,
            progress: watchHistory.progress(for: video.id),
            isWatched: watchHistory.isWatched(video.id),
        )
    }
}

struct VideoCard: View {
    let video: VideoSummary
    let thumbnail: VideoThumbnail

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            thumbnail
                .cardFocusHighlight(VideoThumbnail.shape)

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
    static let shape = RoundedRectangle(cornerRadius: 12)

    let video: VideoSummary
    /// Fraction watched 0...1, nil if never played.
    let progress: Double?
    let isWatched: Bool

    var body: some View {
        Color.gray.opacity(0.2)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: video.thumbnail) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .opacity(isWatched ? 0.6 : 1)
            }
            .clipped()
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

/// Focus style for cards (videos, channels), like the tvOS home screen: the focused card scales
/// up with a spring. Put `.cardFocusHighlight(_:)` on the card's artwork for the ring and shadow.
/// Shadows SwiftUI's own tvOS `CardButtonStyle` inside this module.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CardButtonBody(configuration: configuration)
    }
}

/// `ButtonStyleConfiguration` has no focus state on tvOS; `isFocused` in the style's body view
/// reflects the enclosing button.
private struct CardButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .scaleEffect(scale)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }

    private var scale: CGFloat {
        if configuration.isPressed {
            return 1.02
        }
        return isFocused ? 1.08 : 1
    }
}

extension View {
    /// Clips card artwork to `shape` and, while the enclosing button is focused, draws a ring
    /// (black in light, white in dark appearance) and a drop shadow outside it, so clipping the
    /// artwork never cuts the effect.
    func cardFocusHighlight(_ shape: some InsettableShape) -> some View {
        modifier(CardFocusHighlight(shape: shape))
    }
}

private struct CardFocusHighlight<S: InsettableShape>: ViewModifier {
    let shape: S

    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .clipShape(shape)
            .overlay {
                shape
                    .inset(by: -5)
                    .strokeBorder(Color.primary, lineWidth: 5)
                    .opacity(isFocused ? 1 : 0)
            }
            .shadow(
                color: isFocused ? .black.opacity(0.4) : .clear,
                radius: isFocused ? 20 : 0,
                y: isFocused ? 12 : 0,
            )
            .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}
