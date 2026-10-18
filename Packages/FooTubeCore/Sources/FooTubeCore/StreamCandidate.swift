import Foundation

public enum VideoCodec: Hashable, Sendable {
    /// H.264; `profileLevelID` is the 6 hex digits after `avc1.` (profile, constraints, level), uppercased.
    case h264(profileLevelID: String)
    case other(String)

    /// Parses an RFC 6381 codec string such as `avc1.64002A` or `vp09.00.40.08`.
    public init(codecString: String) {
        let parts = codecString.split(separator: ".", maxSplits: 1)
        if parts.count == 2, parts[0].lowercased() == "avc1", parts[1].count == 6,
           parts[1].allSatisfy(\.isHexDigit)
        {
            self = .h264(profileLevelID: parts[1].uppercased())
        } else {
            self = .other(codecString)
        }
    }

    /// H.264 `level_idc` (e.g. 42 for level 4.2), or nil for other codecs.
    var h264Level: Int? {
        guard case let .h264(profileLevelID) = self else { return nil }
        return Int(profileLevelID.suffix(2), radix: 16)
    }
}

public enum AudioCodec: Hashable, Sendable {
    case aac
    case other(String)
}

/// One stream offered by YouTube for a video, independent of the extraction library.
public struct StreamCandidate: Hashable, Sendable {
    public let url: URL
    public let itag: Int
    public let videoCodec: VideoCodec?
    public let audioCodec: AudioCodec?
    /// Smaller pixel dimension (1080 for 1080p); nil for audio-only.
    public let height: Int?
    public let bitrate: Int?

    public init(url: URL, itag: Int, videoCodec: VideoCodec?, audioCodec: AudioCodec?, height: Int?, bitrate: Int?) {
        self.url = url
        self.itag = itag
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.height = height
        self.bitrate = bitrate
    }

    public var isMuxed: Bool {
        videoCodec != nil && audioCodec != nil
    }
}

/// What the target device can hardware-decode.
public struct DecodeProfile: Sendable {
    public let maxHeight: Int
    public let maxH264Level: Int

    public init(maxHeight: Int, maxH264Level: Int) {
        self.maxHeight = maxHeight
        self.maxH264Level = maxH264Level
    }

    /// Apple TV HD (A8): H.264 up to 1080p60, High/Main Profile level 4.2. No HEVC/VP9/AV1.
    /// Source: https://support.apple.com/en-us/111928
    public static let appleTVHD = DecodeProfile(maxHeight: 1080, maxH264Level: 42)

    func canDecode(_ codec: VideoCodec, height: Int) -> Bool {
        guard let level = codec.h264Level else { return false }
        return level <= maxH264Level && height <= maxHeight
    }
}

public enum StreamSelector {
    /// Best stream containing both audio and video that the device can decode: H.264 within the
    /// profile's level and height, AAC audio. Highest height wins, then highest bitrate.
    public static func bestMuxed(_ candidates: [StreamCandidate], for profile: DecodeProfile) -> StreamCandidate? {
        candidates
            .filter { candidate in
                guard let video = candidate.videoCodec, let height = candidate.height,
                      candidate.audioCodec == .aac else { return false }
                return profile.canDecode(video, height: height)
            }
            .max { lhs, rhs in
                (lhs.height ?? 0, lhs.bitrate ?? 0) < (rhs.height ?? 0, rhs.bitrate ?? 0)
            }
    }
}
