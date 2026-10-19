import AVFoundation
import FooTubeCore
import Observation
import os

/// One playback: owns the player, applies SponsorBlock skips, resumes and records the watch
/// position, and measures what the diagnostics overlay shows.
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
    private let history: WatchHistoryModel
    private var skipPolicy = SkipPolicy(segments: [])
    private var pollTask: Task<Void, Never>?
    private var segmentsTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var endObserver: (any NSObjectProtocol)?
    /// Set once playback runs from the intended start, so the position at 0 before the resume
    /// seek never overwrites the saved one.
    private var tracksProgress = false
    private var lastRecordedPosition = 0.0
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "playback")

    /// Seconds of playback between saved positions.
    private static let recordInterval = 5.0

    nonisolated var id: VideoID {
        source.id
    }

    init(source: PlaybackSource, sponsorBlock: SponsorBlockClient, history: WatchHistoryModel, requestedAt: ContinuousClock.Instant) {
        self.source = source
        self.sponsorBlock = sponsorBlock
        self.history = history
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
        let resume = history.resumePosition(for: id)
        if resume == nil {
            beginPlayback()
        }
        prepareTask = Task { [weak self] in
            await self?.prepare(resumingAt: resume)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordProgress(reachedEnd: true) }
        }
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
        recordProgress()
        prepareTask?.cancel()
        pollTask?.cancel()
        segmentsTask?.cancel()
        noticeTask?.cancel()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        tracksProgress = false
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
        if tracksProgress, abs(seconds - lastRecordedPosition) >= Self.recordInterval {
            recordProgress()
        }
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

    /// Starts playback; from here on the position is saved.
    private func beginPlayback() {
        tracksProgress = true
        let position = player.currentTime().seconds
        lastRecordedPosition = position.isFinite ? position : 0
        player.play()
    }

    /// Once the item is ready: turns subtitles off (the filtered master no longer auto-selects
    /// them; this also overrides the system's automatic subtitle setting), then seeks to `resume`,
    /// if any, and starts playback. A seek is only reliable once the item is ready.
    private func prepare(resumingAt resume: Double?) async {
        guard let item = player.currentItem else { return }
        while item.status == .unknown {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
        }
        guard item.status == .readyToPlay else { return }
        if let legible = try? await source.asset.loadMediaSelectionGroup(for: .legible) {
            item.select(nil, in: legible)
        }
        if let audible = try? await source.asset.loadMediaSelectionGroup(for: .audible) {
            let audio = item.currentMediaSelection.selectedMediaOption(in: audible)?.displayName ?? "none"
            let line = "\(source.id) audio: \(audio) (\(audible.options.count) tracks)"
            logger.info("\(line, privacy: .public)")
        }
        guard let resume, !Task.isCancelled else { return }
        // Up to 3 s before the saved position so AVPlayer can start at a keyframe.
        let finished = await player.seek(
            to: CMTime(seconds: resume, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 3, preferredTimescale: 600),
            toleranceAfter: .zero,
        )
        let line = "\(source.id) resuming at \(resume) s, seek finished: \(finished)"
        logger.info("\(line, privacy: .public)")
        guard !Task.isCancelled else { return }
        beginPlayback()
    }

    /// Saves the position, or marks the video watched at its end. The history skips live streams
    /// (indefinite duration).
    private func recordProgress(reachedEnd: Bool = false) {
        let position = player.currentTime().seconds
        guard tracksProgress, position.isFinite, let item = player.currentItem else { return }
        history.record(id, position: position, duration: item.duration.seconds, reachedEnd: reachedEnd)
        lastRecordedPosition = position
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
