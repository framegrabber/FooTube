import AVFoundation
import FooTubeCore
import Observation
import os

/// One playback: owns the player, applies SponsorBlock skips, and measures what the diagnostics
/// overlay shows.
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

    /// Non-sponsor segment the playhead is in; the player shows a skip button for it.
    private(set) var offeredSegment: SkipSegment?
    /// Brief message after an automatic skip.
    private(set) var notice: String?

    private let sponsorBlock: SponsorBlockClient
    private var skipPolicy = SkipPolicy(segments: [])
    private var pollTask: Task<Void, Never>?
    private var segmentsTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var timeObserver: Any?
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "playback")

    nonisolated var id: VideoID {
        source.id
    }

    init(source: PlaybackSource, sponsorBlock: SponsorBlockClient, requestedAt: ContinuousClock.Instant) {
        self.source = source
        self.sponsorBlock = sponsorBlock
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
        guard timeObserver == nil else { return }
        player.play()
        segmentsTask = Task { [sponsorBlock, id] in
            let segments = await sponsorBlock.segments(for: id)
            guard !Task.isCancelled else { return }
            skipPolicy = SkipPolicy(segments: segments)
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 2), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.timeChanged(to: time.seconds) }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                sample()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        segmentsTask?.cancel()
        noticeTask?.cancel()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player.pause()
        let line = "\(source.id) stopped at \(presentationHeight)p, \(droppedFrames) dropped frames"
        logger.info("\(line, privacy: .public)")
    }

    /// The user pressed the skip button for the offered segment.
    func skipOffered() {
        guard let segment = offeredSegment else { return }
        skipPolicy.markSkipped(segment)
        offeredSegment = nil
        seek(past: segment)
    }

    private func timeChanged(to seconds: Double) {
        guard seconds.isFinite else { return }
        switch skipPolicy.evaluate(at: seconds) {
        case let .autoSkip(segment):
            offeredSegment = nil
            seek(past: segment)
            show(notice: "Skipped \(segment.category.displayName.lowercased())")
        case let .offer(segment):
            if offeredSegment != segment {
                let line = "\(source.id) offering skip of \(segment.category.rawValue) \(segment.start)-\(segment.end)"
                logger.info("\(line, privacy: .public)")
                offeredSegment = segment
            }
        case .none:
            if offeredSegment != nil {
                offeredSegment = nil
            }
        }
    }

    private func seek(past segment: SkipSegment) {
        let line = "\(source.id) skipping \(segment.category.rawValue) \(segment.start)-\(segment.end)"
        logger.info("\(line, privacy: .public)")
        // Zero tolerance before the end: a keyframe-snapped seek could land inside the segment.
        player.seek(
            to: CMTime(seconds: segment.end, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600),
        )
    }

    private func show(notice text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
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
