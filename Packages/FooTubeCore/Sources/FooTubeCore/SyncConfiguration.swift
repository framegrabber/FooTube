import Foundation

/// Where this device syncs: the household's Worker and its bearer token. Valid by construction
/// (`https`, or `http` to `localhost`/`127.0.0.1` for `wrangler dev`; token as the Worker requires).
/// Descriptions and mirrors redact the token, so logging or dumping a configuration never shows it.
public struct SyncConfiguration: Hashable, Sendable {
    /// The Worker answers `not_configured` to shorter tokens (`FooTubeSyncBackend/SPEC.md`).
    public static let minimumTokenLength = 64

    public let url: URL
    public let token: String

    public init(url: URL, token: String) throws(SyncConfigurationError) {
        guard let scheme = url.scheme?.lowercased(), let host = url.host(), !host.isEmpty,
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1"].contains(host.lowercased()))
        else {
            throw .invalidURL("\(url.scheme ?? "no scheme")://\(url.host() ?? "")")
        }
        guard token.count >= Self.minimumTokenLength else { throw .tokenTooShort(length: token.count) }
        // Sent as `Authorization: Bearer <token>`: visible ASCII only, nothing that breaks the header.
        guard token.unicodeScalars.allSatisfy({ (0x21 ... 0x7E).contains($0.value) }) else { throw .tokenNotHeaderSafe }
        self.url = url
        self.token = token
    }
}

extension SyncConfiguration: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "SyncConfiguration(url: \(url.absoluteString), token: <\(token.count) characters>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["url": url, "token": "<\(token.count) characters>"])
    }
}

/// Why a sync configuration was rejected or couldn't be stored. Never carries the token.
public enum SyncConfigurationError: Error, Hashable, Sendable {
    /// The configuration file isn't JSON with the strings `url` and `token`.
    case unreadableFile
    /// Not `https` (or `http` to localhost); carries only `scheme://host`.
    case invalidURL(String)
    case tokenTooShort(length: Int)
    /// The token contains whitespace, control or non-ASCII characters.
    case tokenNotHeaderSafe
    /// A Keychain call failed with this `OSStatus`.
    case keychain(status: Int32)

    public var message: String {
        switch self {
        case .unreadableFile: "Sync configuration file unreadable: expected JSON with \"url\" and \"token\""
        case let .invalidURL(url): "Sync URL must be https (http only to localhost or 127.0.0.1), got \(url)"
        case let .tokenTooShort(length):
            "Sync token has \(length) characters, the Worker needs at least \(SyncConfiguration.minimumTokenLength)"
        case .tokenNotHeaderSafe: "Sync token may only contain visible ASCII characters"
        case let .keychain(status): "Keychain error \(status) for the sync token"
        }
    }
}
