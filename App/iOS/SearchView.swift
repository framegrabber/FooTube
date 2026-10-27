import FooTubeCore
import SwiftUI

/// YouTube search with live suggestions: matching channels in a row above the videos, paging as the
/// list scrolls. Query and results survive tab switches.
struct SearchView: View {
    let catalog: any Catalog

    @State private var model: SearchModel
    @State private var query = ""
    @State private var path: [ChannelRef] = []
    @State private var didApplyLaunchArguments = false

    init(catalog: any Catalog) {
        self.catalog = catalog
        _model = State(initialValue: SearchModel(catalog: catalog))
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Search")
                .searchable(text: $query, prompt: "Search YouTube")
                .searchSuggestions {
                    ForEach(model.suggestions, id: \.self) { suggestion in
                        Label(suggestion, systemImage: "magnifyingglass")
                            .searchCompletion(suggestion)
                    }
                }
                .onSubmit(of: .search) {
                    let text = query.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { return }
                    Task { await model.search(text) }
                }
                .task(id: query) {
                    await model.queryChanged(query)
                }
                .navigationDestination(for: ChannelRef.self) { channel in
                    ChannelView(catalog: catalog, channel: channel)
                }
        }
        .onAppear {
            // Debug/test hooks: `-search <query>` and `-channel <channelID>` launch arguments, once per launch.
            guard !didApplyLaunchArguments else { return }
            didApplyLaunchArguments = true
            if let text = UserDefaults.standard.string(forKey: "search") {
                query = text
            }
            if let id = UserDefaults.standard.string(forKey: "channel") {
                path.append(ChannelRef(id: id, name: nil))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.searchedQuery == nil, !model.isSearching, model.error == nil {
            ContentUnavailableView(
                "Search YouTube",
                systemImage: "magnifyingglass",
                description: Text("Find videos and channels. Open a channel to subscribe."),
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = model.error {
                        ErrorMessage(message: error)
                            .padding(.horizontal)
                    }
                    if model.isSearching {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if let searched = model.searchedQuery, model.results.isEmpty, model.channels.isEmpty, model.error == nil {
                        ContentUnavailableView.search(text: searched)
                    }
                    if !model.channels.isEmpty {
                        ChannelRow(channels: model.channels) { path.append($0.ref) }
                    }
                    VideoGrid(videos: model.results, onReachEnd: model.loadMore, onOpenChannel: { path.append($0) })
                        .padding(.horizontal)
                    if model.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical)
            }
        }
    }
}

/// Matching channels as round avatars in a horizontal row; tapping one opens it.
private struct ChannelRow: View {
    let channels: [ChannelSummary]
    let onOpen: (ChannelSummary) -> Void

    @ScaledMetric(relativeTo: .caption) private var avatarSize: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Channels")
                .font(.headline)
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(channels) { channel in
                        Button {
                            onOpen(channel)
                        } label: {
                            VStack(spacing: 6) {
                                RemoteImage(url: channel.avatar, size: CGSize(width: avatarSize, height: avatarSize))
                                    .frame(width: avatarSize, height: avatarSize)
                                    .clipShape(.circle)
                                Text(channel.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                if let detail = channel.subscriberCount ?? channel.handle {
                                    Text(detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: avatarSize + 40)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
    }
}
