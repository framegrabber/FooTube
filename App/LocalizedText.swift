import FooTubeCore
import Foundation

// User-facing, localized wording for FooTubeCore values. Core keeps its English `message` for logs.

extension CatalogError {
    var userMessage: String {
        switch self {
        case let .requestFailed(reason): String(localized: "Couldn't load from YouTube: \(reason)")
        }
    }
}

extension ResolveError {
    /// The technical detail of `noPlayableStream` stays in the log.
    var userMessage: String {
        switch self {
        case .noPlayableStream:
            #if os(tvOS)
                String(localized: "This video has no format this Apple TV can play.")
            #else
                String(localized: "This video has no format this device can play.")
            #endif
        case let .unavailable(reason): String(localized: "Can't play this video: \(reason)")
        case let .extractionFailed(reason): String(localized: "Couldn't load this video: \(reason)")
        }
    }
}

extension SyncConfigurationError {
    var userMessage: String {
        switch self {
        case .unreadableFile: String(localized: "The sync configuration couldn't be read.")
        case .invalidURL: String(localized: "Enter the server's address starting with https:// (http:// only for localhost).")
        case let .tokenTooShort(length):
            String(localized: "This token has \(length) characters; a sync token has at least \(SyncConfiguration.minimumTokenLength).")
        case .tokenNotHeaderSafe: String(localized: "The token contains spaces or other characters a token can't have. Paste it again.")
        case let .keychain(status): String(localized: "The Keychain reported error \(Int(status)) for the sync token.")
        }
    }
}

extension SyncModel.ConnectError {
    var userMessage: String {
        switch self {
        case let .configuration(error): error.userMessage
        case .server(.unauthorized): String(localized: "The server rejected this token. Paste the sync token, not the inbox token.")
        case .server(.offline): String(localized: "Couldn't reach the server. Check the address and the connection.")
        case .server: String(localized: "The server answered with an error. Check the address.")
        }
    }
}

extension SponsorCategory {
    var localizedName: String {
        switch self {
        case .sponsor: String(localized: "Sponsor")
        case .selfpromo: String(localized: "Self-promotion")
        case .interaction: String(localized: "Interaction reminder")
        case .intro: String(localized: "Intro")
        case .outro: String(localized: "Outro")
        case .preview: String(localized: "Preview")
        case .musicOfftopic: String(localized: "Non-music section")
        case .filler: String(localized: "Filler")
        }
    }

    /// What the category covers, after SponsorBlock's category guidelines.
    var localizedDescription: String {
        switch self {
        case .sponsor: String(localized: "Paid promotion, paid referrals and direct advertisements.")
        case .selfpromo: String(localized: "Unpaid self-promotion: merchandise, donations, or who the creator worked with.")
        case .interaction: String(localized: "A short reminder in the middle of the video to like, subscribe or follow.")
        case .intro: String(localized: "An interval without actual content: a pause, a static frame or a repeating animation.")
        case .outro: String(localized: "Credits and end screens. Not conclusions that still carry information.")
        case .preview: String(localized: "Clips that show what is coming up in this video or in other videos of a series.")
        case .musicOfftopic: String(localized: "In music videos only: parts that are not the song itself.")
        case .filler: String(localized: "Tangents and jokes that are not needed to understand the main content.")
        }
    }
}

extension SkipBehavior {
    var localizedName: String {
        switch self {
        case .skipAutomatically: String(localized: "Skip Automatically")
        case .showButton: String(localized: "Show Skip Button")
        case .off: String(localized: "Off")
        }
    }

    var explanation: String {
        switch self {
        case .skipAutomatically: String(localized: "Playback jumps past the segment once and shows a short notice. Going back into it plays it.")
        case .showButton: String(localized: "A Skip button appears in the player while the segment plays.")
        case .off: String(localized: "Segments of this category play normally.")
        }
    }
}
