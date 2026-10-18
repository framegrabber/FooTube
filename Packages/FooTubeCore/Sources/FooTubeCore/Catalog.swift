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

public protocol Catalog: Sendable {
    func search(_ query: String) async throws(CatalogError) -> ResultsPage
    func moreSearchResults(_ cursor: PageCursor) async throws(CatalogError) -> ResultsPage
}

/// Catalog backed by YouTube's InnerTube API via the vendored b5i/YouTubeKit (`InnerTubeKit`).
public struct InnerTubeCatalog: Catalog {
    /// Thumbnails are downscaled for the A8: the smallest one at least this wide is used.
    static let preferredThumbnailWidth = 480

    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "catalog")

    public init() {}

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

    private func page(_ results: [any YTSearchResult], token: String?, visitorData: String?) -> ResultsPage {
        let items = results.compactMap { ($0 as? YTVideo).flatMap(Self.summary) }
        return ResultsPage(items: items, next: token.map { PageCursor(token: $0, visitorData: visitorData) })
    }

    static func summary(_ video: YTVideo) -> VideoSummary? {
        guard let id = VideoID(video.videoId) else { return nil }
        let byWidth = video.thumbnails.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        let thumbnail = byWidth.first { ($0.width ?? 0) >= preferredThumbnailWidth } ?? byWidth.last
        return VideoSummary(
            id: id,
            title: video.title ?? "",
            channel: video.channel.map { ChannelRef(id: $0.channelId, name: $0.name) },
            duration: video.timeLength.flatMap { $0.isEmpty ? nil : $0 },
            viewCount: video.viewCount,
            published: video.timePosted,
            thumbnail: thumbnail?.url,
        )
    }
}
