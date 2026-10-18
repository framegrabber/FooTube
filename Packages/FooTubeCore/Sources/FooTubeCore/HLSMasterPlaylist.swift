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

    /// AVPlayer starts with the first listed variant (HLS authoring spec); YouTube lists 240p first.
    static let startHeight = 720

    /// Keeps every non-variant line (header, `#EXT-X-MEDIA` renditions) and each
    /// `#EXT-X-STREAM-INF` + URI pair whose video codec is H.264 within the profile. The best
    /// variant at or below `startHeight` is listed first so playback starts sharp; ABR adapts from there.
    /// Returns nil when no variant qualifies.
    public static func filtered(_ text: String, for profile: DecodeProfile) -> Filtered? {
        var otherLines: [Substring] = []
        var variants: [(info: Substring, uri: Substring, height: Int, bandwidth: Int)] = []
        var pending: (info: Substring, height: Int)?
        var dropNextURI = false

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                if let height = decodableHeight(attributes: line, profile: profile) {
                    pending = (line, height)
                    dropNextURI = false
                } else {
                    pending = nil
                    dropNextURI = true
                }
            } else if !line.hasPrefix("#"), !line.isEmpty, pending != nil || dropNextURI {
                if let (info, height) = pending {
                    let bandwidth = attribute("BANDWIDTH", in: info).flatMap { Int($0) } ?? 0
                    variants.append((info, line, height, bandwidth))
                }
                pending = nil
                dropNextURI = false
            } else {
                otherLines.append(line)
            }
        }

        guard !variants.isEmpty else { return nil }
        if let start = variants.indices
            .filter({ variants[$0].height <= startHeight })
            .max(by: { (variants[$0].height, variants[$0].bandwidth) < (variants[$1].height, variants[$1].bandwidth) })
        {
            variants.insert(variants.remove(at: start), at: 0)
        }

        let lines = otherLines.filter { !$0.isEmpty } + variants.flatMap { [$0.info, $0.uri] }
        return Filtered(
            text: lines.joined(separator: "\n") + "\n",
            variantCount: variants.count,
            maxHeight: variants.map(\.height).max() ?? 0,
        )
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

    /// Value of `NAME=value` or `NAME="value"` in an attribute list. The name must start the list
    /// or follow a comma, so `CODECS` does not match `SUPPLEMENTAL-CODECS`.
    private static func attribute(_ name: String, in line: Substring) -> String? {
        var searchStart = line.startIndex
        while let range = line.range(of: "\(name)=", range: searchStart ..< line.endIndex) {
            let preceding = range.lowerBound == line.startIndex ? nil : line[line.index(before: range.lowerBound)]
            guard preceding == ":" || preceding == "," else {
                searchStart = range.upperBound
                continue
            }
            let rest = line[range.upperBound...]
            if rest.hasPrefix("\"") {
                let body = rest.dropFirst()
                return body.firstIndex(of: "\"").map { String(body[..<$0]) }
            }
            return String(rest.prefix { $0 != "," })
        }
        return nil
    }
}
