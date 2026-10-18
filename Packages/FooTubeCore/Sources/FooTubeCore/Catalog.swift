import Foundation
import InnerTubeKit
import os

public struct ChannelRef: Hashable, Sendable {
    public let id: String
    public let name: String?

    public init(id: String, name: String?) {
        self.id = id
        self.name = name
    }
}

/// A video as shown in lists (search results, channel uploads, feed).
public struct VideoSummary: Identifiable, Hashable, Sendable {
    public let id: VideoID
    public let title: String
    public let channel: ChannelRef?
    public let duration: String?
    public let viewCount: String?
    public let published: String?
    public let thumbnail: URL?
}

public extension [VideoSummary] {
    /// YouTube repeats some results across pages; SwiftUI lists need unique IDs.
    func appendingUnique(_ more: [VideoSummary]) -> [VideoSummary] {
        var seen = Set(map(\.id))
        return self + more.filter { seen.insert($0.id).inserted }
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
    public let next: PageCursor?
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

public protocol Catalog: Sendable {
    func search(_ query: String) async throws(CatalogError) -> ResultsPage
    func moreSearchResults(_ cursor: PageCursor) async throws(CatalogError) -> ResultsPage
    /// Channel header plus the first page of its uploads ("Videos" tab), newest first.
    func channel(_ id: String) async throws(CatalogError) -> ChannelPage
    func moreChannelVideos(_ cursor: PageCursor) async throws(CatalogError) -> ResultsPage
}

/// Catalog backed by YouTube's InnerTube API via the vendored b5i/YouTubeKit (`InnerTubeKit`).
public struct InnerTubeCatalog: Catalog {
    /// Thumbnails are downscaled for the A8: the smallest one at least this wide is used.
    static let preferredThumbnailWidth = 480

    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "catalog")

    public init() {}

    public func channel(_ id: String) async throws(CatalogError) -> ChannelPage {
        do {
            let model = YouTubeModel()
            let header = try await ChannelInfosResponse.sendThrowingRequest(youtubeModel: model, data: [.browseId: id])
            let withVideos = try await header.getChannelContentThrowing(forType: .videos, youtubeModel: model)
            let ref = ChannelRef(id: id, name: header.name ?? withVideos.name)
            let videos = (withVideos.channelContentStore[.videos] as? ChannelInfosResponse.Videos)?.items ?? []
            let token = withVideos.channelContentContinuationStore[.videos] ?? nil
            return ChannelPage(
                channel: ref,
                avatar: Self.preferredThumbnail(header.avatarThumbnails, width: 240),
                subscriberCount: header.subscriberCount,
                videos: page(videos, token: token, visitorData: nil, channel: ref),
            )
        } catch {
            logger.error("channel \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw .requestFailed(error.localizedDescription)
        }
    }

    public func moreChannelVideos(_ cursor: PageCursor) async throws(CatalogError) -> ResultsPage {
        do {
            let response = try await ChannelInfosResponse.ContentContinuation<ChannelInfosResponse.Videos>
                .sendThrowingRequest(youtubeModel: YouTubeModel(), data: [.continuation: cursor.token])
            return page(response.contents?.items ?? [], token: response.newContinuationToken, visitorData: nil, channel: cursor.channel)
        } catch {
            logger.error("channel continuation failed: \(error.localizedDescription, privacy: .public)")
            throw .requestFailed(error.localizedDescription)
        }
    }

    public func search(_ query: String) async throws(CatalogError) -> ResultsPage {
        do {
            // YouTubeModel is a non-Sendable class; a fresh one per request keeps this type Sendable.
            let response = try await SearchResponse.sendThrowingRequest(youtubeModel: YouTubeModel(), data: [.query: query])
            return page(response.results, token: response.continuationToken, visitorData: response.visitorData)
        } catch {
            logger.error("search failed: \(error.localizedDescription, privacy: .public)")
            throw .requestFailed(error.localizedDescription)
        }
    }

    public func moreSearchResults(_ cursor: PageCursor) async throws(CatalogError) -> ResultsPage {
        var data: [HeadersList.AddQueryInfo.ContentTypes: String] = [.continuation: cursor.token]
        data[.visitorData] = cursor.visitorData
        do {
            let response = try await SearchResponse.Continuation.sendThrowingRequest(youtubeModel: YouTubeModel(), data: data)
            return page(response.results, token: response.continuationToken, visitorData: cursor.visitorData)
        } catch {
            logger.error("search continuation failed: \(error.localizedDescription, privacy: .public)")
            throw .requestFailed(error.localizedDescription)
        }
    }

    private func page(
        _ results: [any YTSearchResult],
        token: String?,
        visitorData: String?,
        channel: ChannelRef? = nil,
    ) -> ResultsPage {
        let items = results.compactMap { ($0 as? YTVideo).flatMap { Self.summary($0, channel: channel) } }
        return ResultsPage(items: items, next: token.map { PageCursor(token: $0, visitorData: visitorData, channel: channel) })
    }

    /// `channel` fills in the channel when the result has none (channel tabs and their continuations).
    static func summary(_ video: YTVideo, channel: ChannelRef? = nil) -> VideoSummary? {
        guard let id = VideoID(video.videoId) else { return nil }
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

    /// Smallest thumbnail at least `width` wide, else the largest available.
    static func preferredThumbnail(_ thumbnails: [YTThumbnail], width: Int) -> URL? {
        let byWidth = thumbnails.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        return (byWidth.first { ($0.width ?? 0) >= width } ?? byWidth.last)?.url
    }
}
