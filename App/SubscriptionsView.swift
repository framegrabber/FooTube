import FooTubeCore
import SwiftUI

/// Latest uploads from subscribed channels (stored on this device), with a sidebar of the channels
/// to filter the feed by one of them and open its full channel page. The tab owner holds `path`.
struct SubscriptionsView: View {
    let catalog: any Catalog
    @Binding var path: [ChannelRef]

    @Environment(SubscriptionsModel.self) private var subscriptions
    @Environment(FeedModel.self) private var feed
    /// Sidebar selection; nil is "All".
    @State private var selectedID: String?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if subscriptions.subscriptions.isEmpty {
                    VStack(alignment: .leading, spacing: 40) {
                        if let error = subscriptions.lastError {
                            Text(error).foregroundStyle(.red)
                        }
                        Text("No subscriptions yet. Open a channel from search (long-press a video) and choose Subscribe.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(80)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        ChannelSidebar(subscriptions: subscriptions.subscriptions, selectedID: $selectedID)
                            .frame(width: 460)
                        feedColumn
                            .id(selected?.id) // a new filter starts at the top
                    }
                }
            }
            .task(id: subscriptions.subscriptions.map(\.id)) {
                await feed.refresh(subscriptions.subscriptions)
            }
            .navigationDestination(for: ChannelRef.self) { channel in
                ChannelView(catalog: catalog, channel: channel)
            }
        }
    }

    /// The selected channel; nil for "All", also after unsubscribing from the selected channel.
    private var selected: Subscription? {
        selectedID.flatMap { id in subscriptions.subscriptions.first { $0.id == id } }
    }

    private var videos: [VideoSummary] {
        let all = feed.snapshot?.items ?? []
        guard let selected else { return all }
        return all.filter { $0.channel?.id == selected.id }
    }

    private var feedColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if let error = subscriptions.lastError {
                    Text(error).foregroundStyle(.red)
                }
                header
                if let error = feed.lastError {
                    Text(error).foregroundStyle(.red)
                }
                if let selected, videos.isEmpty, !feed.isRefreshing {
                    Text("No recent videos from \(selected.name) in the feed.")
                        .foregroundStyle(.secondary)
                }
                VideoGrid(videos: videos, onOpenChannel: { path.append($0) })
            }
            .padding(.vertical, 80)
            .padding(.horizontal, 60)
        }
        .scrollClipDisabled() // focused cards lift past the scroll view's edges
    }

    private var header: some View {
        HStack(spacing: 32) {
            Text(selected?.name ?? "Latest").font(.headline)
            if feed.isRefreshing {
                ProgressView()
            } else if let fetchedAt = feed.snapshot?.fetchedAt {
                Text("Updated \(fetchedAt, format: .relative(presentation: .named))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let selected {
                Button("Open Channel") { path.append(selected.channel) }
            }
            Button("Refresh") {
                Task { await feed.refresh(subscriptions.subscriptions, force: true) }
            }
            .disabled(feed.isRefreshing)
        }
    }
}

/// "All" plus one row per subscribed channel. Selecting (not just focusing) a row filters the feed, so
/// moving left from the feed into the sidebar never changes the filter by accident.
private struct ChannelSidebar: View {
    let subscriptions: [Subscription]
    @Binding var selectedID: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                SidebarRow(title: "All", isSelected: selectedID == nil) {
                    selectedID = nil
                } icon: {
                    Image(systemName: "square.grid.2x2")
                        .font(.title3)
                        .frame(width: 64, height: 64)
                        .background(.gray.opacity(0.2), in: .circle)
                }
                ForEach(subscriptions) { subscription in
                    SidebarRow(title: subscription.name, isSelected: selectedID == subscription.id) {
                        selectedID = subscription.id
                    } icon: {
                        RemoteImage(url: subscription.avatar, size: CGSize(width: 64, height: 64))
                            .frame(width: 64, height: 64)
                            .clipShape(.circle)
                    }
                }
            }
            .padding(.vertical, 80)
            .padding(.leading, 60)
            .padding(.trailing, 20)
        }
        .scrollClipDisabled() // focused rows grow past the sidebar's edges
        .focusSection()
    }
}

private struct SidebarRow<Icon: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: action) {
            HStack(spacing: 24) {
                icon
                Text(title)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
