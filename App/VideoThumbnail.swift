import FooTubeCore
import SwiftUI

/// 16:9 thumbnail with duration badge and watch state. Not clipped: callers clip to `shape`.
struct VideoThumbnail: View {
    static let cornerRadius: CGFloat = 12
    static let shape = RoundedRectangle(cornerRadius: cornerRadius)
    /// Largest size shown (the tvOS long-press preview); smaller cards decode the same size, so one
    /// decode serves both.
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

/// The long-press menu of a video: "Open <channel>" (when `onOpenChannel` is set) and Add to /
/// Remove from Watch Later.
struct VideoMenu: View {
    let video: VideoSummary
    let onOpenChannel: ((ChannelRef) -> Void)?

    @Environment(WatchLaterModel.self) private var watchLater

    var body: some View {
        if let channel = video.channel, let onOpenChannel {
            Button("Open \(channel.name ?? String(localized: "Channel"))", systemImage: "person.crop.rectangle") {
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
    }
}

extension WatchHistoryModel {
    /// The progress stripe for VoiceOver (a card's accessibility value); "Watched" is already a
    /// visible label.
    func progressDescription(for id: VideoID) -> Text {
        guard !isWatched(id), let fraction = progress(for: id) else {
            return Text(verbatim: "")
        }
        return Text("\(fraction, format: .percent.precision(.fractionLength(0))) watched")
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
            .accessibilityHidden(true) // the card's accessibility value carries it
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
