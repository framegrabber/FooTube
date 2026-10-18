import Foundation

/// A syntactically valid YouTube video ID: 11 characters from `[A-Za-z0-9_-]`.
public struct VideoID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(_ rawValue: String) {
        guard rawValue.utf8.count == 11, rawValue.utf8.allSatisfy(Self.isAllowed) else { return nil }
        self.rawValue = rawValue
    }

    /// Accepts a bare ID or a YouTube URL (`watch?v=`, `youtu.be/`, `shorts/`, `live/`, `embed/`;
    /// www/m/music hosts; scheme optional). Surrounding whitespace is ignored.
    public init?(parsing input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = VideoID(trimmed) {
            self = id
            return
        }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: withScheme), let host = components.host?.lowercased() else {
            return nil
        }
        let segments = components.path.split(separator: "/").map(String.init)

        let candidate: String? = if host == "youtu.be" {
            segments.first
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            if segments.first == "watch" {
                components.queryItems?.first { $0.name == "v" }?.value
            } else if segments.count >= 2, ["shorts", "live", "embed"].contains(segments[0]) {
                segments[1]
            } else {
                nil
            }
        } else {
            nil
        }
        guard let candidate, let id = VideoID(candidate) else { return nil }
        self = id
    }

    public var description: String {
        rawValue
    }

    private static func isAllowed(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a") ... UInt8(ascii: "z"),
             UInt8(ascii: "A") ... UInt8(ascii: "Z"),
             UInt8(ascii: "0") ... UInt8(ascii: "9"),
             UInt8(ascii: "-"), UInt8(ascii: "_"):
            true
        default:
            false
        }
    }
}
