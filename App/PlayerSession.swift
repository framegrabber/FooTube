import AVFoundation
import FooTubeCore
import Observation
import os

/// One playback: owns the player and measures what the diagnostics overlay shows.
@MainActor
@Observable
final class PlayerSession: Identifiable {
    let source: PlaybackSource
    let player: AVPlayer
    /// When the user asked to play (before resolving), for time to first frame.
    let requestedAt: ContinuousClock.Instant
    let resolvedAt: ContinuousClock.Instant

    private(set) var timeToFirstFrame: Duration?
    private(set) var presentationHeight = 0
    private(set) var indicatedBitrate = 0.0
    private(set) var droppedFrames = 0

    private var pollTask: Task<Void, Never>?
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "playback")

    nonisolated var id: VideoID {
        source.id
    }

    init(source: PlaybackSource, requestedAt: ContinuousClock.Instant) {
        self.source = source
        self.requestedAt = requestedAt
        resolvedAt = .now
        player = AVPlayer(playerItem: AVPlayerItem(asset: source.asset))
    }

    /// Called by the player view once the first video frame is ready for display.
    func firstFrameShown() {
        guard timeToFirstFrame == nil else { return }
        let total = ContinuousClock.now - requestedAt
        timeToFirstFrame = total
        let line = "\(source.id) first frame after \(total) (resolve \(resolvedAt - requestedAt)), \(source.stream.summary)"
        logger.info("\(line, privacy: .public)")
    }

    func start() {
        player.play()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        player.pause()
        let line = "\(source.id) stopped at \(presentationHeight)p, \(droppedFrames) dropped frames"
        logger.info("\(line, privacy: .public)")
    }

    private func sample() {
        guard let item = player.currentItem else { return }
        presentationHeight = Int(min(item.presentationSize.width, item.presentationSize.height))
        if let event = item.accessLog()?.events.last {
            indicatedBitrate = event.indicatedBitrate
            droppedFrames = event.numberOfDroppedVideoFrames
        }
    }
}
