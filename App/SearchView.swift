import FooTubeCore
import SwiftUI

/// YouTube search with paging; channels open in the same navigation stack.
struct SearchView: View {
    let catalog: any Catalog

    @State private var query = ""
    @State private var searchedQuery: String?
    @State private var results: [VideoSummary] = []
    @State private var next: PageCursor?
    @State private var isLoadingMore = false
    @State private var error: String?
    @State private var path: [ChannelRef] = []
    @State private var didApplyLaunchArguments = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                VideoGrid(videos: results, onReachEnd: loadMore, onOpenChannel: { path.append($0) })
                    .padding(.horizontal, 80)
            }
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
                next = page.next
            } catch {
                self.error = error.message
            }
        }
    }
}
