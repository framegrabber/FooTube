import Foundation
import os
import YouTubeKit

/// Resolves streams on-device with alexeichhorn/YouTubeKit (local extraction only, no remote fallback).
///
/// Order: (1) the HLS master YouTube offers to its visionOS client, filtered to H.264 variants the
/// device can decode — this covers VOD and live up to 1080p with audio; (2) a muxed H.264+AAC file,
/// checked for HTTP 403 (the web client's muxed URLs need a PO token).
public struct YouTubeKitResolver: StreamResolver {
    private let profile: DecodeProfile
    private let session: URLSession
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "resolver")

    public init(profile: DecodeProfile = .appleTVHD, session: URLSession = .shared) {
        self.profile = profile
        self.session = session
    }

    public func resolve(_ videoID: VideoID) async throws(ResolveError) -> ResolvedStream {
        let video = YouTube(videoID: videoID.rawValue, methods: [.local])

        // What happened with HLS, carried into the error if the muxed fallback fails too.
        let hlsOutcome: String
        do {
            if let master = try await video.livestreams.first(where: { $0.streamType == .hls })?.url {
                if let stream = try await filteredHLS(videoID: videoID, master: master) {
                    logger.info("\(videoID, privacy: .public): \(stream.summary, privacy: .public)")
                    return stream
                }
                hlsOutcome = "HLS offered but no H.264 ≤ \(profile.maxHeight)p variant"
            } else {
                hlsOutcome = "no HLS offered"
            }
        } catch {
            hlsOutcome = "HLS failed (\(error.localizedDescription))"
        }
        logger.info("\(videoID, privacy: .public): \(hlsOutcome, privacy: .public); trying muxed")

        let streams: [YouTubeKit.Stream]
        do {
            // `streams` checks availability first, so its error (private, removed, …) is the precise one.
            streams = try await video.streams
        } catch {
            let mapped = Self.map(error)
            logger.error("\(videoID, privacy: .public): \(mapped.message, privacy: .public)")
            throw mapped
        }

        let candidates = streams.map(Self.candidate)
        guard let best = StreamSelector.bestMuxed(candidates, for: profile), let height = best.height else {
            let error = ResolveError.noPlayableStream(
                detail: "\(hlsOutcome); \(candidates.count) streams, none muxed H.264 ≤ \(profile.maxHeight)p with AAC",
            )
            logger.error("\(videoID, privacy: .public): \(error.message, privacy: .public)")
            throw error
        }
        let status = await firstBytesStatus(best.url)
        guard status == 200 || status == 206 else {
            let error = ResolveError.noPlayableStream(detail: "\(hlsOutcome); muxed itag \(best.itag) returned HTTP \(status)")
            logger.error("\(videoID, privacy: .public): \(error.message, privacy: .public)")
            throw error
        }
        let stream = ResolvedStream(videoID: videoID, url: best.url, kind: .muxed(itag: best.itag, height: height))
        logger.info("\(videoID, privacy: .public): \(stream.summary, privacy: .public)")
        return stream
    }

    private func filteredHLS(videoID: VideoID, master: URL) async throws -> ResolvedStream? {
        let (data, response) = try await session.data(from: master)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "master playlist HTTP \(status)"])
        }
        guard let text = String(data: data, encoding: .utf8),
              let filtered = HLSMasterPlaylist.filtered(text, for: profile) else { return nil }
        let iFramePlaylists = await iFramePlaylists(for: filtered.iFrameSources, videoID: videoID)
        return ResolvedStream(
            videoID: videoID,
            url: master,
            kind: .hls(filtered.adding(iFramePlaylists: iFramePlaylists)),
        )
    }

    /// I-frame playlists for scrubbing thumbnails, built from the low variants' media playlists in
    /// parallel (~0.2 s, never longer than `iFrameDeadline`). One that can't be fetched in time or
    /// rewritten is left out, so the video just has no thumbnails: a declared I-frame playlist
    /// AVPlayer can't load fails the whole video.
    private func iFramePlaylists(for sources: [HLSMasterPlaylist.IFrameSource], videoID: VideoID) async -> [Int: String] {
        guard !sources.isEmpty else { return [:] }
        // Children return a height and maybe a playlist; the deadline child returns nil.
        let built = await withTaskGroup(of: (Int, String?)?.self) { group in
            for source in sources {
                group.addTask { [session] in
                    guard let (data, response) = try? await session.data(from: source.mediaURL),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return (source.height, nil) }
                    return (source.height, HLSMasterPlaylist.iFramePlaylist(fromMedia: String(decoding: data, as: UTF8.self)))
                }
            }
            group.addTask {
                try? await Task.sleep(for: Self.iFrameDeadline)
                return nil
            }
            var built: [Int: String] = [:]
            var answered = 0
            for await result in group {
                guard let (height, playlist) = result else { break } // deadline: stop waiting
                built[height] = playlist
                answered += 1
                if answered == sources.count {
                    break
                }
            }
            group.cancelAll() // the deadline timer, or fetches still running
            return built.compactMapValues(\.self)
        }
        for source in sources where built[source.height] == nil {
            logger.info("\(videoID, privacy: .public): no I-frame playlist from the \(source.height)p variant")
        }
        return built
    }

    /// Longest wait for the thumbnail sources before playback starts without thumbnails.
    static let iFrameDeadline: Duration = .seconds(1)

    private func firstBytesStatus(_ url: URL) async -> Int {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        guard let (_, response) = try? await session.data(for: request) else { return -1 }
        return (response as? HTTPURLResponse)?.statusCode ?? -1
    }

    static func candidate(_ stream: YouTubeKit.Stream) -> StreamCandidate {
        StreamCandidate(
            url: stream.url,
            itag: itag(from: stream.url),
            videoCodec: stream.videoCodec.map(videoCodec),
            audioCodec: stream.audioCodec.map(audioCodec),
            height: stream.videoResolution,
            bitrate: stream.averageBitrate ?? stream.bitrate,
        )
    }

    /// YouTubeKit keeps the itag number internal; googlevideo URLs carry it as a query item.
    private static func itag(from url: URL) -> Int {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "itag" }?.value.flatMap(Int.init) ?? 0
    }

    private static func videoCodec(_ codec: YouTubeKit.VideoCodec) -> VideoCodec {
        switch codec {
        case let .avc1(version): VideoCodec(codecString: "avc1.\(version)")
        case let .vp9(version): .other("vp9.\(version)")
        case let .av1(version): .other("av01.\(version)")
        case let .mp4v(version): .other("mp4v.\(version)")
        case let .unknown(name): .other(name)
        }
    }

    private static func audioCodec(_ codec: YouTubeKit.AudioCodec) -> AudioCodec {
        switch codec {
        case .mp4a: .aac
        case .opus: .other("opus")
        case .ec3: .other("ec-3")
        case .ac3: .other("ac-3")
        case let .unknown(name): .other(name)
        }
    }

    private static func map(_ error: any Error) -> ResolveError {
        guard let error = error as? YouTubeKitError else {
            return .extractionFailed(reason: error.localizedDescription)
        }
        switch error {
        case .videoUnavailable, .videoAgeRestricted, .videoPrivate, .membersOnly, .videoRegionBlocked,
             .recordingUnavailable, .liveStreamError:
            return .unavailable(reason: error.errorDescription ?? error.rawValue)
        default:
            return .extractionFailed(reason: error.errorDescription ?? error.rawValue)
        }
    }
}
