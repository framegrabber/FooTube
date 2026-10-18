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
    private let sponsorBlock: SponsorBlockClient
    private var task: Task<Void, Never>?
    private var clearTask: Task<Void, Never>?

    init(resolver: any StreamResolver, sponsorBlock: SponsorBlockClient) {
        self.resolver = resolver
        self.sponsorBlock = sponsorBlock
    }

    func play(_ id: VideoID) {
        let requestedAt = ContinuousClock.now
        task?.cancel()
        clearTask?.cancel()
        status = .resolving(id)
        task = Task {
            do throws(ResolveError) {
                let stream = try await resolver.resolve(id)
                guard !Task.isCancelled else { return }
                status = .idle
                session = PlayerSession(source: PlaybackSource(stream: stream), sponsorBlock: sponsorBlock, requestedAt: requestedAt)
            } catch {
                guard !Task.isCancelled else { return }
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
