import FooTubeCore
import Observation

/// YouTube search with suggestions and paging, shared by both platforms' Search tab. The view owns
/// the typed query and calls `queryChanged` for each change; results survive tab switches because the
/// view keeps this model in its state.
@MainActor
@Observable
final class SearchModel {
    private(set) var searchedQuery: String?
    private(set) var results: [VideoSummary] = []
    private(set) var channels: [ChannelSummary] = []
    private(set) var isSearching = false
    private(set) var isLoadingMore = false
    private(set) var error: String?
    /// YouTube's completions for the typed text, shown under the search field.
    private(set) var suggestions: [String] = []

    private let catalog: any Catalog
    private var next: PageCursor?

    init(catalog: any Catalog) {
        self.catalog = catalog
    }

    /// Debounces typing: suggestions first, then the search itself. An empty query keeps the last
    /// results; returning to the view (its task re-runs on appear) must not replace paged results
    /// with page 1 again. Call from `.task(id: query)` so a new keystroke cancels the previous wait.
    func queryChanged(_ query: String) async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text != searchedQuery else { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let completions = await (try? catalog.suggestions(text)) ?? []
        guard !Task.isCancelled else { return }
        suggestions = completions
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        await search(text)
    }

    func search(_ text: String) async {
        isSearching = true
        defer { isSearching = false }
        do throws(CatalogError) {
            let page = try await catalog.search(text)
            guard !Task.isCancelled else { return }
            searchedQuery = text
            results = [].appendingUnique(page.items)
            channels = [].appendingUnique(page.channels)
            next = page.next
            error = nil
        } catch {
            self.error = error.userMessage
        }
    }

    /// The next page of results, once the last card appeared.
    func loadMore() {
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
                self.error = error.userMessage
            }
        }
    }
}
