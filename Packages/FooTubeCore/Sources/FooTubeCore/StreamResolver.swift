import Foundation

/// A playable source chosen for a video.
public struct ResolvedStream: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// HLS master playlist already filtered to decodable variants (VOD and live).
        /// `playlist` must be served to AVPlayer instead of the original master at `url`.
        case hls(playlist: String, variantCount: Int, maxHeight: Int)
        /// Single file containing H.264 video and AAC audio (fallback when no HLS is offered).
        case muxed(itag: Int, height: Int)
    }

    public let videoID: VideoID
    public let url: URL
    public let kind: Kind

    public init(videoID: VideoID, url: URL, kind: Kind) {
        self.videoID = videoID
        self.url = url
        self.kind = kind
    }

    /// Short human-readable description for diagnostics.
    public var summary: String {
        switch kind {
        case let .hls(_, variantCount, maxHeight): "HLS, \(variantCount) H.264 variants up to \(maxHeight)p"
        case let .muxed(itag, height): "muxed itag \(itag), \(height)p"
        }
    }
}

public enum ResolveError: Error, Hashable, Sendable {
    /// YouTube returned streams, but none this device can play.
    case noPlayableStream(detail: String)
    /// The video cannot be played (age restriction, private, region block, members only, unavailable).
    case unavailable(reason: String)
    /// Extraction itself failed (network, YouTube changes, signature solving).
    case extractionFailed(reason: String)

    public var message: String {
        switch self {
        case let .noPlayableStream(detail): "No stream this Apple TV can play: \(detail)"
        case let .unavailable(reason): "Video unavailable: \(reason)"
        case let .extractionFailed(reason): "Extraction failed: \(reason)"
        }
    }
}

public protocol StreamResolver: Sendable {
    func resolve(_ videoID: VideoID) async throws(ResolveError) -> ResolvedStream
}
