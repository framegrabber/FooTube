import FooTubeCore
import SwiftUI

/// Channel header and its uploads, newest first, with paging.
struct ChannelView: View {
    let catalog: any Catalog
    let channel: ChannelRef
    var onOpenChannel: ((ChannelRef) -> Void)?

    @Environment(SubscriptionsModel.self) private var subscriptions
    @State private var page: ChannelPage?
    @State private var videos: [VideoSummary] = []
    @State private var next: PageCursor?
    @State private var isLoadingMore = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                header
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                VideoGrid(videos: videos, onReachEnd: loadMore, onOpenChannel: onOpenChannel)
            }
            .padding(80)
        }
        .task(id: channel.id) { await load() }
    }

    private var header: some View {
        HStack(spacing: 32) {
            AsyncImage(url: page?.avatar) { image in
                image.resizable()
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 120, height: 120)
            .clipShape(.circle)
            VStack(alignment: .leading, spacing: 8) {
                Text(page?.channel.name ?? channel.name ?? "Channel")
                    .font(.title2)
                if let subscribers = page?.subscriberCount {
                    Text(subscribers)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(subscriptions.isSubscribed(channel.id) ? "Unsubscribe" : "Subscribe") {
                subscriptions.toggle(page?.channel ?? channel, avatar: page?.avatar)
            }
        }
    }

    private func load() async {
        do throws(CatalogError) {
            let loaded = try await catalog.channel(channel.id)
            page = loaded
            videos = [].appendingUnique(loaded.videos.items)
            next = loaded.videos.next
            error = nil
        } catch {
            self.error = error.message
        }
    }

    private func loadMore() {
        guard let cursor = next, !isLoadingMore else { return }
        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            do throws(CatalogError) {
                let more = try await catalog.moreChannelVideos(cursor)
                videos = videos.appendingUnique(more.items)
                next = more.next
            } catch {
                self.error = error.message
            }
        }
    }
}
