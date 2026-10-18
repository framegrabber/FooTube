import FooTubeCore
import SwiftUI

/// Grid of video cards. Selecting plays; the context menu (long press) opens the channel.
/// `onReachEnd` is called when the last card appears, for paging.
struct VideoGrid: View {
    let videos: [VideoSummary]
    var onReachEnd: (() -> Void)?
    var onOpenChannel: ((ChannelRef) -> Void)?

    @Environment(PlaybackController.self) private var playback

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 48), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 64) {
            ForEach(videos) { video in
                Button {
                    playback.play(video.id)
                } label: {
                    VideoCard(video: video)
                }
                .buttonStyle(.borderless)
                .contextMenu {
                    if let channel = video.channel, let onOpenChannel {
                        Button("Open \(channel.name ?? "Channel")") { onOpenChannel(channel) }
                    }
                }
                .onAppear {
                    if video.id == videos.last?.id {
                        onReachEnd?()
                    }
                }
            }
        }
    }
}

struct VideoCard: View {
    let video: VideoSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsyncImage(url: video.thumbnail) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if let duration = video.duration {
                    Text(duration)
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.75), in: .rect(cornerRadius: 6))
                        .padding(8)
                }
            }
            .clipShape(.rect(cornerRadius: 12))

            Text(video.title)
                .font(.callout)
                .lineLimit(2, reservesSpace: true)
            Text([video.channel?.name, video.viewCount, video.published].compactMap(\.self).joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
