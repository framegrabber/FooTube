import Foundation

/// A syntactically valid YouTube video ID: 11 characters from `[A-Za-z0-9_-]`.
public struct VideoID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(_ rawValue: String) {
        guard rawValue.utf8.count == 11, rawValue.utf8.allSatisfy(Self.isAllowed) else { return nil }
        self.rawValue = rawValue
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
