import FooTubeCore
import SwiftUI

/// YouTube search with paging: matching channels in a row above the videos; channels open in the same
/// navigation stack, whose `path` the tab owner holds. Query and results survive tab switches and
/// returns from the tab bar; the user starts a new search with the keyboard.
struct SearchView: View {
    let catalog: any Catalog
    @Binding var path: [ChannelRef]

    @State private var query = ""
    @State private var searchedQuery: String?
    @State private var results: [VideoSummary] = []
    @State private var channels: [ChannelSummary] = []
    @State private var next: PageCursor?
    @State private var isLoadingMore = false
    @State private var error: String?
    @State private var didApplyLaunchArguments = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 48) {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    }
                    if !channels.isEmpty {
                        ChannelRow(channels: channels) { path.append($0.ref) }
                    }
                    VideoGrid(videos: results, onReachEnd: loadMore, onOpenChannel: { path.append($0) })
                }
                .padding(.horizontal, 80)
            }
            .scrollClipDisabled() // focused lockups lift past the scroll view's edges
            .searchable(text: $query, prompt: "Search YouTube")
            .task(id: query) {
                // Debounce typing. An empty query keeps the last results; returning to this view
                // (task re-runs on appear) must not replace paged results with page 1 again.
                let text = query.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty, text != searchedQuery else { return }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                await search(text)
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

    private func search(_ text: String) async {
        do throws(CatalogError) {
            let page = try await catalog.search(text)
            guard !Task.isCancelled else { return }
            searchedQuery = text
            results = [].appendingUnique(page.items)
            channels = [].appendingUnique(page.channels)
            next = page.next
            error = nil
        } catch {
            self.error = error.message
        }
    }

    private func loadMore() {
        guard let cursor = next, !isLoadingMore else { return }
        isLoadingMore = true
        let forQuery = searchedQuery
        Task {
            defer { isLoadingMore = false }
            do throws(CatalogError) {
                let page = try await catalog.moreSearchResults(cursor)
                guard forQuery == searchedQuery else { return } // a new search started meanwhile
                results = results.appendingUnique(page.items)
                channels = channels.appendingUnique(page.channels)
                next = page.next
            } catch {
                self.error = error.message
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
