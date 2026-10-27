import FooTubeCore
import SwiftUI

/// YouTube search with paging: matching channels in a row above the videos; channels open in the same
/// navigation stack, whose `path` the tab owner holds. Query and results survive tab switches and
/// returns from the tab bar; the user starts a new search with the keyboard.
struct SearchView: View {
    let catalog: any Catalog
    @Binding var path: [ChannelRef]

    @State private var model: SearchModel
    @State private var query = ""
    @State private var didApplyLaunchArguments = false

    init(catalog: any Catalog, path: Binding<[ChannelRef]>) {
        self.catalog = catalog
        _path = path
        _model = State(initialValue: SearchModel(catalog: catalog))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 48) {
                    if let error = model.error {
                        ErrorMessage(message: error)
                    }
                    if model.isSearching {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if let searchedQuery = model.searchedQuery, model.results.isEmpty, model.channels.isEmpty, model.error == nil {
                        ContentUnavailableView.search(text: searchedQuery)
                    }
                    if !model.channels.isEmpty {
                        ChannelRow(channels: model.channels) { path.append($0.ref) }
                    }
                    VideoGrid(videos: model.results, onReachEnd: model.loadMore, onOpenChannel: { path.append($0) })
                    if model.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 80)
            }
            .scrollClipDisabled() // focused lockups lift past the scroll view's edges
            .searchable(text: $query, prompt: "Search YouTube")
            .searchSuggestions {
                ForEach(model.suggestions, id: \.self) { suggestion in
                    Text(suggestion).searchCompletion(suggestion)
                }
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
}

/// Matching channels as round avatar lockups in a horizontal shelf; selecting one opens it.
private struct ChannelRow: View {
    let channels: [ChannelSummary]
    let onOpen: (ChannelSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Channels").font(.headline)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 48) {
                    ForEach(channels) { channel in
                        Button {
                            onOpen(channel)
                        } label: {
                            ChannelTile(channel: channel)
                        }
                    }
                }
                .padding(.vertical, 24) // room for the focused avatar's lift and shadow
            }
            .scrollClipDisabled()
            .buttonStyle(.borderless)
            .buttonBorderShape(.circle)
        }
        .focusSection()
    }
}

/// Label of a borderless channel button: the avatar carries the focus effect, the text stays plain.
private struct ChannelTile: View {
    let channel: ChannelSummary

    var body: some View {
        VStack(spacing: 16) {
            RemoteImage(url: channel.avatar, size: CGSize(width: 160, height: 160))
                .frame(width: 160, height: 160)
                .clipShape(.circle)
                .hoverEffect(.highlight)
            Text(channel.name)
                .font(.callout)
                .lineLimit(1)
            if let detail = channel.subscriberCount ?? channel.handle {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 240)
    }
}
