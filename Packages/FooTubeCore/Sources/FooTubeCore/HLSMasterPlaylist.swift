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
        /// Low variants whose media playlists can become I-frame playlists; empty when the master
        /// has decodable I-frame playlists of its own. Not declared in `text` until built and added
        /// with `adding(iFramePlaylists:)`.
        public let iFrameSources: [IFrameSource]
        /// I-frame playlists declared in `text` by FooTube, by URI relative to the master; served
        /// from memory so AVPlayer can always load them.
        public let iFramePlaylists: [String: String]

        /// This master declaring the given I-frame playlists, built from `iFrameSources` (keyed by
        /// height; heights without a source are ignored). Declare only what was built: a declared
        /// I-frame playlist AVPlayer cannot load fails the whole video (CoreMedia -12642).
        public func adding(iFramePlaylists built: [Int: String]) -> Filtered {
            var lines: [String] = []
            var playlists = iFramePlaylists
            for source in iFrameSources {
                guard let playlist = built[source.height] else { continue }
                let uri = "iframes-\(source.height).m3u8"
                lines.append("#EXT-X-I-FRAME-STREAM-INF:\(source.attributes),URI=\"\(uri)\"")
                playlists[uri] = playlist
            }
            var master = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            master.insert(contentsOf: lines, at: master.firstIndex { $0.hasPrefix("#EXT-X-STREAM-INF:") } ?? master.endIndex)
            return Filtered(
                text: master.joined(separator: "\n"),
                variantCount: variantCount,
                maxHeight: maxHeight,
                iFrameSources: iFrameSources,
                iFramePlaylists: playlists,
            )
        }
    }

    /// A variant to build an I-frame playlist from.
    public struct IFrameSource: Hashable, Sendable {
        public let height: Int
        public let mediaURL: URL
        /// `BANDWIDTH`, `CODECS` (video only) and `RESOLUTION` of the variant, for its I-frame line.
        let attributes: String
    }

    /// AVPlayer starts with the first listed variant (HLS authoring spec); YouTube lists 240p first.
    static let startHeight = 720

    /// Heights whose variants become I-frame playlists. Every YouTube TS segment starts with an IDR,
    /// so a whole segment is a valid I-frame; low variants keep the bytes per thumbnail small.
    static let iFrameMaxHeight = 240

    /// Keeps every non-variant line (header, `#EXT-X-MEDIA` renditions) and each
    /// `#EXT-X-STREAM-INF` + URI pair whose video codec is H.264 within the profile. The best
    /// variant at or below `startHeight` is listed first so playback starts sharp; ABR adapts from there.
    /// Renditions get default flags for the original audio and no subtitles (`withPreferredDefaults`).
    /// Without decodable I-frame playlists of its own, the cheapest variant of each height up to
    /// `iFrameMaxHeight` becomes an `iFrameSources` entry, for scrubbing thumbnails.
    /// Returns nil when no variant qualifies.
    public static func filtered(_ text: String, for profile: DecodeProfile) -> Filtered? {
        var otherLines: [Substring] = []
        var variants: [(info: Substring, uri: Substring, height: Int, bandwidth: Int)] = []
        var pending: (info: Substring, height: Int)?
        var dropNextURI = false
        var hasIFramePlaylist = false

        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.hasPrefix("#EXT-X-I-FRAME-STREAM-INF:") {
                // Trick-play playlist; its URI is an attribute, so it is a single line.
                if decodableHeight(attributes: line, profile: profile) != nil {
                    otherLines.append(line)
                    hasIFramePlaylist = true
                }
            } else if line.hasPrefix("#EXT-X-STREAM-INF:") {
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

        var iFrameSources: [IFrameSource] = []
        if !hasIFramePlaylist {
            let low = Dictionary(grouping: variants.filter { $0.height <= iFrameMaxHeight }, by: \.height)
            for height in low.keys.sorted() {
                guard let cheapest = low[height]?.min(by: { $0.bandwidth < $1.bandwidth }),
                      let media = URL(string: String(cheapest.uri)),
                      let codec = videoCodecs(attributes: cheapest.info).first,
                      let resolution = attribute("RESOLUTION", in: cheapest.info) else { continue }
                let attributes = "BANDWIDTH=\(cheapest.bandwidth),CODECS=\"\(codec)\",RESOLUTION=\(resolution)"
                iFrameSources.append(IFrameSource(height: height, mediaURL: media, attributes: attributes))
            }
        }

        let lines = withPreferredDefaults(otherLines.filter { !$0.isEmpty }) + variants.flatMap { [String($0.info), String($0.uri)] }
        return Filtered(
            text: lines.joined(separator: "\n") + "\n",
            variantCount: variants.count,
            maxHeight: variants.map(\.height).max() ?? 0,
            iFrameSources: iFrameSources,
            iFramePlaylists: [:],
        )
    }

    /// Turns a VOD variant's media playlist into an I-frame playlist (RFC 8216 §4.3.3.6): each
    /// segment, with its duration, becomes one I-frame, the whole segment being the I-frame resource.
    /// Valid because each of YouTube's TS segments starts with its own PAT/PMT, SPS/PPS and an IDR,
    /// so it decodes alone. Nil for live playlists (no `EXT-X-ENDLIST`: a served snapshot would go
    /// stale), byte-range or fMP4 (`EXT-X-MAP`) segments, which are not self-contained files, and
    /// input without segments.
    public static func iFramePlaylist(fromMedia text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.first == "#EXTM3U", lines.contains("#EXT-X-ENDLIST"),
              !lines.contains(where: { $0.hasPrefix("#EXT-X-BYTERANGE") || $0.hasPrefix("#EXT-X-MAP") }),
              lines.contains(where: { !$0.hasPrefix("#") }) else { return nil }
        let version = lines.lazy.compactMap { $0.hasPrefix(versionTag) ? Int($0.dropFirst(versionTag.count)) : nil }.first ?? 1
        let header = ["#EXTM3U", "\(versionTag)\(max(version, 4))", "#EXT-X-I-FRAMES-ONLY"]
        let body = lines.dropFirst().filter { !$0.hasPrefix(versionTag) && $0 != "#EXT-X-I-FRAMES-ONLY" }.map(String.init)
        return (header + body).joined(separator: "\n") + "\n"
    }

    private static let versionTag = "#EXT-X-VERSION:"

    private static let mediaTag = "#EXT-X-MEDIA:"

    /// Rewrites `DEFAULT`/`AUTOSELECT` of `#EXT-X-MEDIA` renditions:
    /// - Audio groups that contain a rendition YouTube marks as original (`acont=original` in
    ///   `YT-EXT-XTAGS`): that rendition becomes `DEFAULT=YES,AUTOSELECT=YES`, all others (AI or human
    ///   dubs) `DEFAULT=NO,AUTOSELECT=NO`. YouTube marks every track `DEFAULT=NO,AUTOSELECT=YES`, so
    ///   AVPlayer would pick the dub matching the system language. Groups without such a marker
    ///   (single "Default" track) stay as they are.
    /// - Subtitles and closed captions: `DEFAULT=NO,AUTOSELECT=NO`, so they stay off until chosen.
    ///
    /// `AUTOSELECT=NO` only excludes a rendition from automatic selection; it stays in the player's menus.
    private static func withPreferredDefaults(_ lines: [Substring]) -> [String] {
        let renditions: [AttributeList?] = lines.map { $0.hasPrefix(mediaTag) ? AttributeList($0.dropFirst(mediaTag.count)) : nil }
        var originalByGroup: [Substring: Int] = [:]
        for (index, entry) in renditions.enumerated() {
            guard let rendition = entry, rendition["TYPE"] == "AUDIO", let group = rendition["GROUP-ID"],
                  let tags = rendition["YT-EXT-XTAGS"], youTubeTags(tags)["acont"] == "original" else { continue }
            if originalByGroup[group] == nil {
                originalByGroup[group] = index
            }
        }

        return lines.indices.map { index in
            let line = lines[index]
            guard var rendition = renditions[index] else { return String(line) }
            switch rendition["TYPE"] {
            case "AUDIO"?:
                guard let group = rendition["GROUP-ID"], let original = originalByGroup[group] else { return String(line) }
                rendition.setDefault(index == original)
            case "SUBTITLES"?, "CLOSED-CAPTIONS"?:
                rendition.setDefault(false)
            default:
                return String(line)
            }
            return mediaTag + rendition.text
        }
    }

    /// Attribute list of a tag, split on commas outside quoted strings (YouTube URIs contain commas).
    private struct AttributeList {
        private var items: [Substring]

        init(_ list: Substring) {
            items = []
            var start = list.startIndex
            var quoted = false
            for index in list.indices {
                if list[index] == "\"" {
                    quoted.toggle()
                } else if list[index] == ",", !quoted {
                    items.append(list[start ..< index])
                    start = list.index(after: index)
                }
            }
            items.append(list[start...])
        }

        /// Value with surrounding quotes removed.
        subscript(name: String) -> Substring? {
            guard let item = items.first(where: { $0.hasPrefix("\(name)=") }) else { return nil }
            let value = item.dropFirst(name.count + 1)
            guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
            return value.dropFirst().dropLast()
        }

        mutating func setDefault(_ isDefault: Bool) {
            let value = isDefault ? "YES" : "NO"
            set("DEFAULT", to: value)
            set("AUTOSELECT", to: value)
        }

        private mutating func set(_ name: String, to value: String) {
            let item = Substring("\(name)=\(value)")
            if let index = items.firstIndex(where: { $0.hasPrefix("\(name)=") }) {
                items[index] = item
            } else {
                items.append(item)
            }
        }

        var text: String {
            items.joined(separator: ",")
        }
    }

    /// Decodes `YT-EXT-XTAGS`: base64url (unpadded) protobuf of repeated `{1: key, 2: value}` string
    /// pairs, e.g. `acont=original`, `lang=en-US`. Malformed input yields no tags.
    private static func youTubeTags(_ encoded: Substring) -> [String: String] {
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), let entries = lengthDelimitedFields([UInt8](data)[...]) else { return [:] }
        var tags: [String: String] = [:]
        for (number, entry) in entries where number == 1 {
            guard let fields = lengthDelimitedFields(entry),
                  let key = fields.first(where: { $0.number == 1 }),
                  let value = fields.first(where: { $0.number == 2 }) else { continue }
            tags[String(decoding: key.bytes, as: UTF8.self)] = String(decoding: value.bytes, as: UTF8.self)
        }
        return tags
    }

    /// Length-delimited fields of a protobuf message (other wire types are skipped); nil if malformed.
    private static func lengthDelimitedFields(_ bytes: ArraySlice<UInt8>) -> [(number: Int, bytes: ArraySlice<UInt8>)]? {
        var fields: [(number: Int, bytes: ArraySlice<UInt8>)] = []
        var index = bytes.startIndex
        func varint() -> Int? {
            var result = 0
            var shift = 0
            while index < bytes.endIndex, shift < 64 {
                let byte = bytes[index]
                index += 1
                result |= Int(byte & 0x7F) << shift
                if byte & 0x80 == 0 {
                    return result
                }
                shift += 7
            }
            return nil
        }
        func skip(_ count: Int) -> Bool {
            guard count >= 0, bytes.endIndex - index >= count else { return false }
            index += count
            return true
        }
        while index < bytes.endIndex {
            guard let key = varint() else { return nil }
            switch key & 0x7 {
            case 0:
                guard varint() != nil else { return nil }
            case 1:
                guard skip(8) else { return nil }
            case 2:
                guard let length = varint() else { return nil }
                let start = index
                guard skip(length) else { return nil }
                fields.append((key >> 3, bytes[start ..< index]))
            case 5:
                guard skip(4) else { return nil }
            default:
                return nil
            }
        }
        return fields
    }

    private static func decodableHeight(attributes line: Substring, profile: DecodeProfile) -> Int? {
        guard let resolution = attribute("RESOLUTION", in: line) else { return nil }
        let dimensions = resolution.split(separator: "x").compactMap { Int($0) }
        guard dimensions.count == 2, let height = dimensions.min() else { return nil }

        let videoCodecs = videoCodecs(attributes: line)
        guard videoCodecs.count == 1, profile.canDecode(VideoCodec(codecString: videoCodecs[0]), height: height) else { return nil }
        return height
    }

    /// The video entries of `CODECS` (e.g. `avc1.4D400C`), without audio or subtitle codecs.
    private static func videoCodecs(attributes line: Substring) -> [String] {
        guard let codecs = attribute("CODECS", in: line) else { return [] }
        return codecs.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { codec in videoCodecPrefixes.contains { codec.lowercased().hasPrefix($0) } }
    }

    /// RFC 6381 sample-entry prefixes of video codecs; everything else in CODECS (audio, subtitles) is ignored.
    private static let videoCodecPrefixes = ["avc1", "avc3", "hvc1", "hev1", "dvh1", "dvhe", "vp08", "vp09", "av01"]

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
