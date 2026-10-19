import FooTubeCore
import Observation

/// Resolves a video and owns the current `PlayerSession`; every screen plays through this.
@MainActor
@Observable
final class PlaybackController {
    enum Status: Equatable {
        case idle
        case resolving(VideoID)
        case failed(String)
    }

    var session: PlayerSession?
    private(set) var status: Status = .idle

    private let resolver: any StreamResolver
    private let catalog: any Catalog
    private let sponsorBlock: SponsorBlockClient
    private let history: WatchHistoryModel
    private var task: Task<Void, Never>?
    private var clearTask: Task<Void, Never>?

    init(resolver: any StreamResolver, catalog: any Catalog, sponsorBlock: SponsorBlockClient, history: WatchHistoryModel) {
        self.resolver = resolver
        self.catalog = catalog
        self.sponsorBlock = sponsorBlock
        self.history = history
    }

    /// Plays a video from a list; its summary is kept in the watch history (History tab).
    func play(_ video: VideoSummary) {
        start(video.id, summary: video)
    }

    /// Plays by ID only (`-play` launch argument); History shows it once it was played from a list.
    func play(_ id: VideoID) {
        start(id, summary: nil)
    }

    private func start(_ id: VideoID, summary: VideoSummary?) {
        let requestedAt = ContinuousClock.now
        task?.cancel()
        clearTask?.cancel()
        status = .resolving(id)
        task = Task {
            do throws(ResolveError) {
                let stream = try await resolver.resolve(id)
                guard !Task.isCancelled else { return }
                status = .idle
                session = PlayerSession(
                    source: PlaybackSource(stream: stream),
                    video: summary,
                    catalog: catalog,
                    sponsorBlock: sponsorBlock,
                    history: history,
                    requestedAt: requestedAt,
                )
            } catch {
                guard !Task.isCancelled else { return }
                // Up next failed: close the finished player so the message is visible.
                session = nil
                fail(error.message)
            }
        }
    }

    /// Shows a message in the status banner for a few seconds.
    func fail(_ message: String) {
        status = .failed(message)
        clearTask?.cancel()
        clearTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            status = .idle
        }
    }
}
