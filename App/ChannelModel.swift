import FooTubeCore
import Observation

/// One channel page (header and uploads, newest first) with paging, shared by both platforms'
/// channel view.
@MainActor
@Observable
final class ChannelModel {
    let channel: ChannelRef
    private(set) var page: ChannelPage?
    private(set) var videos: [VideoSummary] = []
    private(set) var isLoadingMore = false
    private(set) var error: String?

    private let catalog: any Catalog
    private var next: PageCursor?

    init(catalog: any Catalog, channel: ChannelRef) {
        self.catalog = catalog
        self.channel = channel
    }

    /// The name to show: the loaded one, else the one the link carried.
    var name: String? {
        page?.channel.name ?? channel.name
    }

    func load() async {
        guard page == nil else { return } // `.task` re-runs when navigating back; keep paged results
        do throws(CatalogError) {
            let loaded = try await catalog.channel(channel.id)
            page = loaded
            videos = [].appendingUnique(loaded.videos.items)
            next = loaded.videos.next
            error = nil
        } catch {
            self.error = error.userMessage
        }
    }

    /// The next page of uploads, once the last card appeared.
    func loadMore() {
        guard let cursor = next, !isLoadingMore else { return }
        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            do throws(CatalogError) {
                let more = try await catalog.moreChannelVideos(cursor)
                videos = videos.appendingUnique(more.items)
                next = more.next
            } catch {
                self.error = error.userMessage
            }
        }
    }
}
