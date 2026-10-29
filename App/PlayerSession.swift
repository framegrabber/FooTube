import AVFoundation
import AVKit
import FooTubeCore
import Observation
import os
import UIKit

/// One playback: owns the player, applies SponsorBlock skips, resumes and records the watch
/// position, loads the video's chapters (tvOS: chapter markers; iOS: `chapters` for the player's
/// chapter list), proposes a related video at the end on tvOS ("Up next"), and logs playback metrics
/// (time to first frame, resolution, dropped frames).
@MainActor
@Observable
final class PlayerSession: Identifiable {
    let source: PlaybackSource
    let player: AVPlayer
    /// When the user asked to play (before resolving), for time to first frame.
    let requestedAt: ContinuousClock.Instant
    let resolvedAt: ContinuousClock.Instant

    /// Playback metrics for the log lines at first frame and stop.
    private var timeToFirstFrame: Duration?
    private var presentationHeight = 0
    private var droppedFrames = 0

    /// Non-sponsor segment the playhead is in; the player shows a skip button for it.
    private(set) var offeredSegment: SkipSegment?
    /// Brief message after an automatic skip.
    private(set) var notice: String?
    #if os(tvOS)
        /// Related video proposed when this one ends; nil until the watch page has loaded, or if none fits.
        private(set) var upNext: VideoSummary?
    #else
        /// The video's chapters once the watch page has loaded; empty for videos without chapters.
        private(set) var chapters: [Chapter] = []
        /// Playhead in seconds, updated twice a second (the chapter list marks the current chapter).
        private(set) var position = 0.0
    #endif

    /// Title, channel and thumbnail for the History tab; nil when played by ID only.
    private let video: VideoSummary?
    private let catalog: any Catalog
    private let sponsorBlock: SponsorBlockClient
    private let history: WatchHistoryModel
    private let skipSettings: SkipSettings
    private var skipPolicy = SkipPolicy(segments: [])
    private var pollTask: Task<Void, Never>?
    private var segmentsTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var detailsTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var endObserver: (any NSObjectProtocol)?
    /// Set once playback runs from the intended start, so the position at 0 before the resume
    /// seek never overwrites the saved one.
    private var tracksProgress = false
    private var lastRecordedPosition = 0.0
    private var isStopped = false
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "playback")

    /// Seconds of playback between saved positions.
    private static let recordInterval = 5.0
    #if os(tvOS)
        /// Seconds the Up next countdown runs after the video ends before the proposal plays.
        private static let upNextCountdown = 10.0
        private static let chapterArtwork = (width: 320, height: 180)
    #endif

    /// Title for the player and Now Playing; nil when played by ID only.
    var title: String? {
        video?.title
    }

    nonisolated var id: VideoID {
        source.id
    }

    init(
        source: PlaybackSource,
        video: VideoSummary?,
        catalog: any Catalog,
        sponsorBlock: SponsorBlockClient,
        history: WatchHistoryModel,
        skipSettings: SkipSettings,
        requestedAt: ContinuousClock.Instant,
    ) {
        self.source = source
        self.video = video
        self.catalog = catalog
        self.sponsorBlock = sponsorBlock
        self.history = history
        self.skipSettings = skipSettings
        self.requestedAt = requestedAt
        resolvedAt = .now
        player = AVPlayer(playerItem: AVPlayerItem(asset: source.asset))
    }

    /// Called by the player view once the first video frame is ready for display.
    func firstFrameShown() {
        guard timeToFirstFrame == nil else { return }
        let total = ContinuousClock.now - requestedAt
        timeToFirstFrame = total
        log("first frame after \(total) (resolve \(resolvedAt - requestedAt)), \(source.stream.summary)")
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
        detailsTask = Task { [weak self] in
            await self?.loadDetails()
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordProgress(reachedEnd: true) }
        }
        segmentsTask = Task { [sponsorBlock, id, skipSettings] in
            let segments = await sponsorBlock.segments(for: id)
            guard !Task.isCancelled else { return }
            skipPolicy = SkipPolicy(segments: segments, settings: skipSettings)
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
        guard !isStopped else { return }
        isStopped = true
        recordProgress()
        prepareTask?.cancel()
        detailsTask?.cancel()
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
        log("stopped at \(presentationHeight)p, \(droppedFrames) dropped frames")
    }

    #if os(tvOS)
        /// Up next was accepted: stops and empties the player. AVKit expects the next item right away
        /// and otherwise replays this finished one from the start while the next video resolves.
        func finish() {
            stop()
            player.replaceCurrentItem(with: nil)
        }
    #else
        /// The user chose a chapter in the chapter list.
        func seek(to chapter: Chapter) {
            log("seeking to chapter at \(chapter.start)")
            position = chapter.start
            player.seek(
                to: CMTime(seconds: chapter.start, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600),
            )
        }
    #endif

    /// The user pressed the skip button for the offered segment.
    func skipOffered() {
        guard let segment = offeredSegment else { return }
        skipPolicy.markSkipped(segment)
        offeredSegment = nil
        seek(past: segment)
    }

    private func timeChanged(to seconds: Double) {
        guard seconds.isFinite else { return }
        #if os(iOS)
            position = seconds
        #endif
        if tracksProgress, abs(seconds - lastRecordedPosition) >= Self.recordInterval {
            recordProgress()
        }
        switch skipPolicy.evaluate(at: seconds) {
        case let .autoSkip(segment):
            offeredSegment = nil
            seek(past: segment)
            show(notice: String(localized: "\(segment.category.localizedName) skipped"))
        case let .offer(segment):
            if offeredSegment != segment {
                log("offering skip of \(segment.category.rawValue) \(segment.start)-\(segment.end)")
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
        guard let item = await readyItem() else { return }
        if let legible = try? await source.asset.loadMediaSelectionGroup(for: .legible) {
            item.select(nil, in: legible)
        }
        if let audible = try? await source.asset.loadMediaSelectionGroup(for: .audible) {
            let audio = item.currentMediaSelection.selectedMediaOption(in: audible)?.displayName ?? "none"
            log("audio: \(audio) (\(audible.options.count) tracks)")
        }
        guard let resume, !Task.isCancelled else { return }
        // Up to 3 s before the saved position so AVPlayer can start at a keyframe.
        let finished = await player.seek(
            to: CMTime(seconds: resume, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 3, preferredTimescale: 600),
            toleranceAfter: .zero,
        )
        log("resuming at \(resume) s, seek finished: \(finished)")
        guard !Task.isCancelled else { return }
        beginPlayback()
    }

    /// The current item once it is ready to play; nil if it failed or the task was cancelled.
    private func readyItem() async -> AVPlayerItem? {
        guard let item = player.currentItem else { return nil }
        while item.status == .unknown {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return nil }
        }
        return item.status == .readyToPlay ? item : nil
    }

    /// Loads the watch page. tvOS: proposes the first fitting related video for the end, then shows
    /// the chapters as chapter markers, first titles only, then again with their thumbnails once
    /// loaded. iOS (no system Up next or chapter markers): publishes `chapters` for the player's
    /// chapter list. Live streams (no finite duration) get neither.
    private func loadDetails() async {
        let details: VideoDetails
        do throws(CatalogError) {
            details = try await catalog.details(id)
        } catch {
            log("no chapters or up next: \(error.message)", error: true)
            return
        }
        guard let item = await readyItem(), item.duration.seconds.isFinite else { return }
        #if os(tvOS)
            let duration = item.duration.seconds
            if let next = details.upNext(after: id, isWatched: { history.isWatched($0) }) {
                await propose(next, on: item)
            }
            guard !details.chapters.isEmpty, !Task.isCancelled else { return }
            item.navigationMarkerGroups = Self.markerGroups(details.chapters, duration: duration, artwork: [:])
            var artwork: [URL: Data] = [:]
            for url in details.chapters.compactMap(\.thumbnail) {
                let request = RemoteImageLoader.Request(url: url, pixelWidth: Self.chapterArtwork.width, pixelHeight: Self.chapterArtwork.height)
                artwork[url] = await RemoteImageLoader.shared.image(for: request)?.jpegData(compressionQuality: 0.8)
                guard !Task.isCancelled else { return }
            }
            item.navigationMarkerGroups = Self.markerGroups(details.chapters, duration: duration, artwork: artwork)
            if let next = upNext?.id {
                let id = source.id
                logger.info("\(id, privacy: .private(mask: .hash)) \(details.chapters.count) chapters, up next: \(next, privacy: .private(mask: .hash))")
            } else {
                log("\(details.chapters.count) chapters, no up next")
            }
        #else
            guard !details.chapters.isEmpty, !Task.isCancelled else { return }
            chapters = details.chapters
            log("\(details.chapters.count) chapters")
        #endif
    }

    #if os(tvOS)
        /// Sets the item's content proposal; the player presents it when the video ends.
        private func propose(_ next: VideoSummary, on item: AVPlayerItem) async {
            var preview: UIImage?
            if let url = next.thumbnail {
                preview = await RemoteImageLoader.shared.image(for: .init(url: url, pixelWidth: 960, pixelHeight: 540))
            }
            guard !Task.isCancelled else { return }
            let proposal = AVContentProposal(contentTimeForTransition: .indefinite, title: next.title, previewImage: preview)
            proposal.automaticAcceptanceInterval = Self.upNextCountdown
            item.nextContentProposal = proposal
            upNext = next
        }

        /// One chapter marker per chapter, each lasting until the next one (the last until the end).
        private static func markerGroups(_ chapters: [Chapter], duration: Double, artwork: [URL: Data]) -> [AVNavigationMarkersGroup] {
            let markers = chapters.enumerated().compactMap { index, chapter -> AVTimedMetadataGroup? in
                let end = min(index + 1 < chapters.count ? chapters[index + 1].start : duration, duration)
                guard chapter.start < end else { return nil }
                let title = AVMutableMetadataItem()
                title.identifier = .commonIdentifierTitle
                title.value = chapter.title as NSString
                title.extendedLanguageTag = "und"
                var items: [AVMetadataItem] = [title]
                if let data = chapter.thumbnail.flatMap({ artwork[$0] }) {
                    let image = AVMutableMetadataItem()
                    image.identifier = .commonIdentifierArtwork
                    image.value = data as NSData
                    image.dataType = kCMMetadataBaseDataType_JPEG as String
                    image.extendedLanguageTag = "und"
                    items.append(image)
                }
                let range = CMTimeRange(start: CMTime(seconds: chapter.start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
                return AVTimedMetadataGroup(items: items, timeRange: range)
            }
            return [AVNavigationMarkersGroup(title: nil, timedNavigationMarkers: markers)]
        }
    #endif

    /// Saves the position, or marks the video watched at its end. The history skips live streams
    /// (indefinite duration).
    private func recordProgress(reachedEnd: Bool = false) {
        let position = player.currentTime().seconds
        guard tracksProgress, position.isFinite, let item = player.currentItem else { return }
        history.record(id, position: position, duration: item.duration.seconds, reachedEnd: reachedEnd, video: video)
        lastRecordedPosition = position
    }

    private func seek(past segment: SkipSegment) {
        log("skipping \(segment.category.rawValue) \(segment.start)-\(segment.end)")
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
            droppedFrames = event.numberOfDroppedVideoFrames
        }
    }

    /// Logs `line` (no video data) after the video ID, which is hashed: lines about one video stay
    /// recognizable together, but the log doesn't show what was watched.
    private func log(_ line: String, error: Bool = false) {
        let id = source.id
        if error {
            logger.error("\(id, privacy: .private(mask: .hash)) \(line, privacy: .public)")
        } else {
            logger.info("\(id, privacy: .private(mask: .hash)) \(line, privacy: .public)")
        }
    }
}
