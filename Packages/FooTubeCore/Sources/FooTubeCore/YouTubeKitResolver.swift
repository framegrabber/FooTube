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
        return ResolvedStream(
            videoID: videoID,
            url: master,
            kind: .hls(playlist: filtered.text, variantCount: filtered.variantCount, maxHeight: filtered.maxHeight),
        )
    }

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
