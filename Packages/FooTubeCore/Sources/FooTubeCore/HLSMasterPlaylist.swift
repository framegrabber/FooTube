import Foundation

/// Filters a YouTube HLS master playlist down to variants the device can hardware-decode.
///
/// YouTube's masters mix H.264 and VP9 variants up to 4K. AVPlayer would happily pick a VP9 or
/// > 1080p variant it can only software-decode, so we drop those before AVPlayer sees the list.
public enum HLSMasterPlaylist {
    public struct Filtered: Hashable, Sendable {
        public let text: String
        public let variantCount: Int
        public let maxHeight: Int
    }

    /// Keeps every non-variant line (header, `#EXT-X-MEDIA` renditions) and each
    /// `#EXT-X-STREAM-INF` + URI pair whose video codec is H.264 within the profile.
    /// Returns nil when no variant qualifies.
    public static func filtered(_ text: String, for profile: DecodeProfile) -> Filtered? {
        var output: [Substring] = []
        var variantCount = 0
        var maxHeight = 0
        var dropNextURI = false

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                if let height = decodableHeight(attributes: line, profile: profile) {
                    output.append(line)
                    variantCount += 1
                    maxHeight = max(maxHeight, height)
                    dropNextURI = false
                } else {
                    dropNextURI = true
                }
            } else if dropNextURI, !line.hasPrefix("#"), !line.isEmpty {
                dropNextURI = false
            } else {
                output.append(line)
            }
        }

        guard variantCount > 0 else { return nil }
        return Filtered(text: output.joined(separator: "\n"), variantCount: variantCount, maxHeight: maxHeight)
    }

    private static func decodableHeight(attributes line: Substring, profile: DecodeProfile) -> Int? {
        guard let codecs = attribute("CODECS", in: line), let resolution = attribute("RESOLUTION", in: line) else {
            return nil
        }
        let dimensions = resolution.split(separator: "x").compactMap { Int($0) }
        guard dimensions.count == 2, let height = dimensions.min() else { return nil }

        let videoCodecs = codecs.split(separator: ",")
            .map { VideoCodec(codecString: $0.trimmingCharacters(in: .whitespaces)) }
            .filter {
                if case let .other(raw) = $0 {
                    !raw.hasPrefix("mp4a")
                } else {
                    true
                }
            }
        guard videoCodecs.count == 1, profile.canDecode(videoCodecs[0], height: height) else { return nil }
        return height
    }

    /// Value of `NAME=value` or `NAME="value"` in an attribute list.
    private static func attribute(_ name: String, in line: Substring) -> String? {
        guard let range = line.range(of: "\(name)=") else { return nil }
        let rest = line[range.upperBound...]
        if rest.hasPrefix("\"") {
            let body = rest.dropFirst()
            return body.firstIndex(of: "\"").map { String(body[..<$0]) }
        }
        return String(rest.prefix { $0 != "," })
    }
}
