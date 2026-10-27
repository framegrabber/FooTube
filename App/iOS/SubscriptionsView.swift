import FooTubeCore
import SwiftUI

/// Latest uploads from subscribed channels, with a row of the channels above to filter the feed by
/// one of them and open its channel page. Pull to refresh.
struct SubscriptionsView: View {
    let catalog: any Catalog
    /// Switches to the Search tab (empty state action).
    let onSearch: () -> Void

    @Environment(SubscriptionsModel.self) private var subscriptions
    @Environment(FeedModel.self) private var feed
    @State private var path: [ChannelRef] = []
    /// Channel filter; nil is "All".
    @State private var selectedID: String?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if subscriptions.subscriptions.isEmpty {
                    ContentUnavailableView {
                        Label("No Subscriptions", systemImage: "person.2")
                    } description: {
                        Text("Search for a channel, open it and choose Subscribe. New videos from your channels appear here.")
                    } actions: {
                        if let error = subscriptions.lastError {
                            ErrorMessage(message: error)
                        }
                        Button("Search YouTube", action: onSearch)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    feedList
                }
            }
            .navigationTitle("Subscriptions")
            .toolbar {
                if feed.isRefreshing {
                    ToolbarItem(placement: .topBarTrailing) {
                        ProgressView()
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

    private var feedList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ChannelFilter(subscriptions: subscriptions.subscriptions, selectedID: $selectedID)
                VStack(alignment: .leading, spacing: 16) {
                    if let error = subscriptions.lastError {
                        ErrorMessage(message: error)
                    }
                    if let error = feed.lastError {
                        ErrorMessage(message: error)
                    }
                    header
                    if let selected, videos.isEmpty, !feed.isRefreshing {
                        Text("No recent videos from \(selected.name) in the feed.")
                            .foregroundStyle(.secondary)
                    }
                    VideoGrid(videos: videos, onOpenChannel: { path.append($0) })
                        .id(selected?.id) // a new filter starts with fresh cards
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
        .refreshable {
            await feed.refresh(subscriptions.subscriptions, force: true)
        }
    }

    /// The filter's name with a link to its channel page, and when the feed was updated.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let selected {
                Button {
                    path.append(selected.channel)
                } label: {
                    HStack(spacing: 4) {
                        Text(selected.name)
                            .font(.headline)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Opens the channel"))
            }
            if let fetchedAt = feed.snapshot?.fetchedAt {
                Text("Updated \(fetchedAt, format: .relative(presentation: .named))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// "All" plus one avatar per subscribed channel in a horizontal row; tapping one filters the feed.
private struct ChannelFilter: View {
    let subscriptions: [Subscription]
    @Binding var selectedID: String?

    @ScaledMetric(relativeTo: .caption) private var avatarSize: CGFloat = 56

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                FilterItem(title: String(localized: "All"), isSelected: selectedID == nil, width: avatarSize + 20) {
                    selectedID = nil
                } icon: {
                    Image(systemName: "square.grid.2x2")
                        .font(.title3)
                        .frame(width: avatarSize, height: avatarSize)
                        .background(.fill.tertiary, in: .circle)
                }
                ForEach(subscriptions) { subscription in
                    FilterItem(title: subscription.name, isSelected: selectedID == subscription.id, width: avatarSize + 20) {
                        selectedID = selectedID == subscription.id ? nil : subscription.id
                    } icon: {
                        RemoteImage(url: subscription.avatar, size: CGSize(width: avatarSize, height: avatarSize))
                            .frame(width: avatarSize, height: avatarSize)
                            .clipShape(.circle)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }
}

private struct FilterItem<Icon: View>: View {
    let title: String
    let isSelected: Bool
    let width: CGFloat
    let action: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                icon
                    .padding(3)
                    .overlay {
                        Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                    }
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
