import Foundation

/// A `footube://` link, for Shortcuts and other apps that open FooTube on iPhone or iPad:
/// - `footube://play?v=<video>` plays the video;
/// - `footube://watch-later?v=<video>[&title=<title>]` adds it to Watch Later.
/// `<video>` is anything `VideoID(parsing:)` accepts: a bare ID or a YouTube URL, percent-encoded or
/// not. An unencoded URL's own query splits into the link's query items, so the first `v` item with a
/// video ID counts (`v=https://m.youtube.com/watch?feature=share&v=<id>` gives two `v` items).
public enum AppLink: Hashable, Sendable {
    case play(VideoID)
    case watchLater(VideoID, title: String?)

    public static let scheme = "footube"

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.lazy.filter({ $0.name == "v" }).compactMap({ $0.value.flatMap(VideoID.init(parsing:)) }).first
        else { return nil }
        switch components.host?.lowercased() {
        case "play":
            self = .play(id)
        case "watch-later":
            let title = components.queryItems?.first { $0.name == "title" }?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self = .watchLater(id, title: title?.isEmpty == false ? title : nil)
        default:
            return nil
        }
    }
}

public extension VideoSummary {
    /// A video known only by its ID and maybe a title (browser inbox, `footube://` links): the ID
    /// stands in for a missing title; the thumbnail is YouTube's standard one for every video.
    static func bare(_ id: VideoID, title: String?) -> VideoSummary {
        VideoSummary(
            id: id,
            title: title ?? id.rawValue,
            channel: nil,
            duration: nil,
            viewCount: nil,
            published: nil,
            thumbnail: URL(string: "https://i.ytimg.com/vi/\(id.rawValue)/hqdefault.jpg"),
        )
    }
}
