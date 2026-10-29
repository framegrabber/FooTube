import Foundation
import InnerTubeKit
import os

public struct ChannelRef: Codable, Hashable, Sendable {
    public let id: String
    public let name: String?

    public init(id: String, name: String?) {
        self.id = id
        self.name = name
    }
}

/// A video as shown in lists (search results, channel uploads, feed).
public struct VideoSummary: Identifiable, Codable, Hashable, Sendable {
    public let id: VideoID
    public let title: String
    public let channel: ChannelRef?
    public let duration: String?
    public let viewCount: String?
    public let published: String?
    public let thumbnail: URL?
}

public extension Array where Element: Identifiable {
    /// YouTube repeats some results across pages; SwiftUI lists need unique IDs.
    func appendingUnique(_ more: [Element]) -> [Element] {
        var seen = Set(map(\.id))
        return self + more.filter { seen.insert($0.id).inserted }
    }
}

/// A channel as shown in search results.
public struct ChannelSummary: Identifiable, Codable, Hashable, Sendable {
    /// Channel ID (`UC…`).
    public let id: String
    public let name: String
    public let handle: String?
    public let subscriberCount: String?
    public let videoCount: String?
    public let avatar: URL?

    public var ref: ChannelRef {
        ChannelRef(id: id, name: name)
    }
}

/// Opaque position for loading the next page.
public struct PageCursor: Hashable, Sendable {
    let token: String
    let visitorData: String?
    /// Channel continuation pages omit channel info; it is re-attached from here.
    var channel: ChannelRef?
}

public struct ResultsPage: Sendable {
    public let items: [VideoSummary]
    /// Channels among search results; empty for channel uploads (and so the feed).
    public let channels: [ChannelSummary]
    public let next: PageCursor?

    init(items: [VideoSummary], channels: [ChannelSummary] = [], next: PageCursor?) {
        self.items = items
        self.channels = channels
        self.next = next
    }
}

public enum CatalogError: Error, Hashable, Sendable {
    case requestFailed(String)

    public var message: String {
        switch self {
        case let .requestFailed(reason): "Couldn't load from YouTube: \(reason)"
        }
    }
}

public struct ChannelPage: Sendable {
    public let channel: ChannelRef
    public let avatar: URL?
    public let subscriberCount: String?
    public let videos: ResultsPage
}

/// A chapter from the video description, for the player's chapter markers.
public struct Chapter: Hashable, Sendable {
    public let title: String
    /// Seconds from the start of the video.
    public let start: Double
    public let thumbnail: URL?
}

/// What the watch page adds to a video: its chapters, its channel and YouTube's related videos.
public struct VideoDetails: Sendable {
    /// Ordered by start, starts unique; empty when the video has no chapters.
    public let chapters: [Chapter]
    /// ID of the video's own channel.
    public let channelID: String?
    public let related: [VideoSummary]

    public init(chapters: [Chapter], channelID: String?, related: [VideoSummary]) {
        self.chapters = chapters
        self.channelID = channelID
        self.related = related
    }

    /// The video to propose after `current`: a related video that isn't `current`, isn't watched to
    /// the end, and has a duration (live streams and upcoming premieres have none). One from the
    /// video's own channel comes first: YouTube's related list without a login is largely generic
    /// popular videos.
    public func upNext(after current: VideoID, isWatched: (VideoID) -> Bool) -> VideoSummary? {
        let fitting = related.filter { $0.id != current && $0.duration != nil && !isWatched($0.id) }
        return fitting.first { channelID != nil && $0.channel?.id == channelID } ?? fitting.first
    }
}

public protocol Catalog: Sendable {
    func search(_ query: String) async throws(CatalogError) -> ResultsPage
    func moreSearchResults(_ cursor: PageCursor) async throws(CatalogError) -> ResultsPage
    /// Channel header plus the first page of its uploads ("Videos" tab), newest first.
    func channel(_ id: String) async throws(CatalogError) -> ChannelPage
    func moreChannelVideos(_ cursor: PageCursor) async throws(CatalogError) -> ResultsPage
    /// Chapters and related videos of a video (YouTube's watch page).
    func details(_ id: VideoID) async throws(CatalogError) -> VideoDetails
    /// Search suggestions for what has been typed so far, most relevant first.
    func suggestions(_ query: String) async throws(CatalogError) -> [String]
}

/// Catalog backed by YouTube's InnerTube API via the vendored b5i/YouTubeKit (`InnerTubeKit`).
public struct InnerTubeCatalog: Catalog {
    /// Thumbnails are downscaled for the A8: the smallest one at least this wide is used.
    static let preferredThumbnailWidth = 480
    static let preferredAvatarWidth = 240
    static let preferredChapterThumbnailWidth = 320

    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "catalog")

    public init() {}

    /// YouTubeModel is a non-Sendable class; a fresh one per request keeps this type Sendable.
    /// Requests use the device's preferred language (titles and descriptions in the owner's language,
    /// e.g. `de-DE`) and region, falling back to `en-US`. `FeedMerger.age(of:)` parses English and
    /// German relative ages.
    private static func model() -> YouTubeModel {
        let model = YouTubeModel()
        let language = Locale.preferredLanguages.first
            .flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
        model.selectedLocale = "\(language)-\(Locale.current.region?.identifier ?? "US")"
        return model
    }

    public func channel(_ id: String) async throws(CatalogError) -> ChannelPage {
        do {
            let model = Self.model()
            let header = try await ChannelInfosResponse.sendThrowingRequest(youtubeModel: model, data: [.browseId: id])
            // A channel without a "Videos" tab (only Shorts or live streams) has no uploads to list.
            var uploads = ChannelVideosResponse()
            if let params = header.requestParams[.videos] {
                uploads = try await ChannelVideosResponse.sendThrowingRequest(youtubeModel: model, data: [.browseId: id, .params: params])
            }
            let ref = ChannelRef(id: id, name: header.name ?? uploads.name)
            return ChannelPage(
                channel: ref,
                avatar: Self.preferredThumbnail(header.avatarThumbnails, width: Self.preferredAvatarWidth),
                subscriberCount: header.subscriberCount,
                videos: Self.page(uploads.videos, token: uploads.continuation, visitorData: nil, channel: ref),
            )
        } catch {
            logger.error("channel \(id, privacy: .private(mask: .hash)) failed: \(error.localizedDescription, privacy: .public)")
            throw .requestFailed(error.localizedDescription)
        }
    }

    public func moreChannelVideos(_ cursor: PageCursor) async throws(CatalogError) -> ResultsPage {
        do {
            let response = try await ChannelVideosResponse.Continuation
                .sendThrowingRequest(youtubeModel: Self.model(), data: [.continuation: cursor.token])
            return Self.page(response.videos, token: response.continuation, visitorData: nil, channel: cursor.channel)
        } catch {
            logger.error("channel continuation failed: \(error.localizedDescription, privacy: .public)")
            throw .requestFailed(error.localizedDescription)
        }
    }

    public func search(_ query: String) async throws(CatalogError) -> ResultsPage {
        do {
            let response = try await SearchResponse.sendThrowingRequest(youtubeModel: Self.model(), data: [.query: query])
            return Self.page(response.results, token: response.continuationToken, visitorData: response.visitorData)
        } catch {
            logger.error("search failed: \(error.localizedDescription, privacy: .public)")
            throw .requestFailed(error.localizedDescription)
        }
    }

    public func moreSearchResults(_ cursor: PageCursor) async throws(CatalogError) -> ResultsPage {
        var data: [HeadersList.AddQueryInfo.ContentTypes: String] = [.continuation: cursor.token]
        data[.visitorData] = cursor.visitorData
        do {
            let response = try await SearchResponse.Continuation.sendThrowingRequest(youtubeModel: Self.model(), data: data)
            return Self.page(response.results, token: response.continuationToken, visitorData: cursor.visitorData)
        } catch {
            logger.error("search continuation failed: \(error.localizedDescription, privacy: .public)")
            throw .requestFailed(error.localizedDescription)
        }
    }

    public func details(_ id: VideoID) async throws(CatalogError) -> VideoDetails {
        do {
            let response = try await MoreVideoInfosResponse.sendThrowingRequest(youtubeModel: Self.model(), data: [.query: id.rawValue])
            return VideoDetails(
                chapters: Self.chapters(response.chapters ?? []),
                channelID: response.channel.flatMap { $0.channelId.isEmpty ? nil : $0.channelId },
                related: Self.page(response.recommendedVideos, token: nil, visitorData: nil).items,
            )
        } catch {
            logger.error("details \(id, privacy: .private(mask: .hash)) failed: \(error.localizedDescription, privacy: .public)")
            throw .requestFailed(error.localizedDescription)
        }
    }

    public func suggestions(_ query: String) async throws(CatalogError) -> [String] {
        do {
            return try await AutoCompletionResponse.sendThrowingRequest(youtubeModel: Self.model(), data: [.query: query]).autoCompletionEntries
        } catch {
            logger.error("suggestions failed: \(error.localizedDescription, privacy: .public)")
            throw .requestFailed(error.localizedDescription)
        }
    }

    /// Chapters without a title or start are dropped; the rest are ordered by start, one per start.
    static func chapters(_ chapters: [MoreVideoInfosResponse.Chapter]) -> [Chapter] {
        var seen = Set<Int>()
        return chapters
            .compactMap { chapter -> (Int, Chapter)? in
                guard let start = chapter.startTimeSeconds, start >= 0,
                      let title = chapter.title, !title.isEmpty else { return nil }
                return (start, Chapter(title: title, start: Double(start), thumbnail: preferredThumbnail(chapter.thumbnail, width: preferredChapterThumbnailWidth)))
            }
            .sorted { $0.0 < $1.0 }
            .filter { seen.insert($0.0).inserted }
            .map(\.1)
    }

    static func page(
        _ results: [any YTSearchResult],
        token: String?,
        visitorData: String?,
        channel: ChannelRef? = nil,
    ) -> ResultsPage {
        ResultsPage(
            items: results.compactMap { ($0 as? YTVideo).flatMap { summary($0, channel: channel) } },
            channels: [].appendingUnique(results.compactMap { ($0 as? YTChannel).flatMap { channelSummary($0) } }),
            next: token.map { PageCursor(token: $0, visitorData: visitorData, channel: channel) },
        )
    }

    /// `channel` fills in the channel when the result has none (channel tabs and their continuations).
    /// Members-only videos are dropped: they don't play without a member's Google login.
    static func summary(_ video: YTVideo, channel: ChannelRef? = nil) -> VideoSummary? {
        guard video.memberOnly != true, let id = VideoID(video.videoId) else { return nil }
        return VideoSummary(
            id: id,
            title: video.title ?? "",
            channel: video.channel.map { ChannelRef(id: $0.channelId, name: $0.name) } ?? channel,
            duration: video.timeLength.flatMap { $0.isEmpty ? nil : $0 },
            viewCount: video.viewCount,
            published: video.timePosted,
            thumbnail: preferredThumbnail(video.thumbnails, width: preferredThumbnailWidth),
        )
    }

    /// Channels without an ID or any name to show are dropped.
    static func channelSummary(_ channel: YTChannel) -> ChannelSummary? {
        guard !channel.channelId.isEmpty, let name = channel.name ?? channel.handle, !name.isEmpty else { return nil }
        return ChannelSummary(
            id: channel.channelId,
            name: name,
            handle: channel.handle,
            subscriberCount: channel.subscriberCount,
            videoCount: channel.videoCount,
            avatar: preferredThumbnail(channel.thumbnails, width: preferredAvatarWidth),
        )
    }

    /// Smallest thumbnail at least `width` wide, else the largest available.
    static func preferredThumbnail(_ thumbnails: [YTThumbnail], width: Int) -> URL? {
        let byWidth = thumbnails.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        return (byWidth.first { ($0.width ?? 0) >= width } ?? byWidth.last)?.url
    }
}

/// A channel's "Videos" tab, decoded by InnerTubeKit's `ChannelInfosResponse` plus the "Members only"
/// badge: InnerTubeKit's lockup decoder (`YTVideo.decodeLockupJSON`, used for channel tabs) never sets
/// `YTVideo.memberOnly`, so the badge is read from the raw lockups here.
struct ChannelVideosResponse: YouTubeResponse {
    static var headersType: HeaderTypes {
        ChannelInfosResponse.headersType
    }

    static var parametersValidationList: ValidationList {
        ChannelInfosResponse.parametersValidationList
    }

    var name: String?
    var videos: [YTVideo] = []
    var continuation: String?

    static func decodeJSON(json: JSON) -> ChannelVideosResponse {
        let channel = ChannelInfosResponse.decodeJSON(json: json)
        let tab = channel.channelContentStore[.videos] as? ChannelInfosResponse.Videos
        return ChannelVideosResponse(
            name: channel.name,
            videos: markingMembersOnly(tab?.items ?? [], in: json),
            continuation: channel.channelContentContinuationStore[.videos] ?? nil,
        )
    }

    /// A further page of the "Videos" tab.
    struct Continuation: YouTubeResponse {
        static var headersType: HeaderTypes {
            ChannelInfosResponse.ContentContinuation<ChannelInfosResponse.Videos>.headersType
        }

        static var parametersValidationList: ValidationList {
            ChannelInfosResponse.ContentContinuation<ChannelInfosResponse.Videos>.parametersValidationList
        }

        var videos: [YTVideo] = []
        var continuation: String?

        static func decodeJSON(json: JSON) -> Continuation {
            let page = ChannelInfosResponse.Videos.decodeContinuation(json: json)
            return Continuation(
                videos: markingMembersOnly(page.contents?.items ?? [], in: json),
                continuation: page.newContinuationToken,
            )
        }
    }

    private static func markingMembersOnly(_ results: [any YTSearchResult], in json: JSON) -> [YTVideo] {
        let membersOnly = membersOnlyVideoIDs(in: json)
        return results.compactMap { result in
            guard var video = result as? YTVideo else { return nil }
            if membersOnly.contains(video.videoId) {
                video.memberOnly = true
            }
            return video
        }
    }

    /// IDs of the lockups in a channel tab (first page or continuation) that carry a "Members only" badge.
    private static func membersOnlyVideoIDs(in json: JSON) -> Set<String> {
        let tabItems = json["contents", "twoColumnBrowseResultsRenderer", "tabs"].arrayValue
            .flatMap { $0["tabRenderer", "content", "richGridRenderer", "contents"].arrayValue }
        let continuationItems = json["onResponseReceivedActions"].arrayValue
            .flatMap { $0["appendContinuationItemsAction", "continuationItems"].arrayValue }
        let ids = (tabItems + continuationItems).compactMap { item -> String? in
            let lockup = item["richItemRenderer", "content", "lockupViewModel"]
            let rows = lockup["metadata", "lockupMetadataViewModel", "metadata", "contentMetadataViewModel", "metadataRows"].arrayValue
            let badges = rows.flatMap { $0["badges"].arrayValue }
            return badges.contains { $0["badgeViewModel", "badgeStyle"].string == "BADGE_MEMBERS_ONLY" } ? lockup["contentId"].string : nil
        }
        return Set(ids)
    }
}
