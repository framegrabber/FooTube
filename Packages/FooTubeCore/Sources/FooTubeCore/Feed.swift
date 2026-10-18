import Foundation
import os

/// Latest uploads across subscriptions, newest first.
public struct FeedSnapshot: Codable, Hashable, Sendable {
    public let fetchedAt: Date
    public let items: [VideoSummary]

    public init(fetchedAt: Date, items: [VideoSummary]) {
        self.fetchedAt = fetchedAt
        self.items = items
    }
}

public struct FeedService: Sendable {
    /// Channels fetched in parallel; keeps the A8 and YouTube rate limits comfortable.
    static let maxConcurrentChannels = 4
    static let limit = 120

    private let catalog: any Catalog
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "feed")

    public init(catalog: any Catalog) {
        self.catalog = catalog
    }

    /// Fetches the first uploads page of every channel, at most `maxConcurrentChannels` at a time.
    /// A channel that fails keeps its videos from `previous` (logged). Returns nil only if every
    /// channel failed. Equal ages are ordered by channel order, not by network completion.
    public func refresh(_ channels: [ChannelRef], previous: FeedSnapshot? = nil) async -> FeedSnapshot? {
        var pages = [[VideoSummary]](repeating: [], count: channels.count)
        var failures = 0
        await withTaskGroup(of: (Int, [VideoSummary]?).self) { group in
            var pending = channels.enumerated().makeIterator()
            func enqueue() {
                guard let (index, channel) = pending.next() else { return }
                group.addTask { [catalog, logger] in
                    do throws(CatalogError) {
                        return try await (index, catalog.channel(channel.id).videos.items)
                    } catch {
                        logger.error("\(channel.id, privacy: .public): \(error.message, privacy: .public)")
                        return (index, nil)
                    }
                }
            }
            for _ in 0 ..< Self.maxConcurrentChannels {
                enqueue()
            }
            for await (index, page) in group {
                if let page {
                    pages[index] = page
                } else {
                    failures += 1
                    pages[index] = previous?.items.filter { $0.channel?.id == channels[index].id } ?? []
                }
                enqueue()
            }
        }
        logger.info("refreshed \(channels.count) channels, \(failures) failed")
        guard failures < channels.count || channels.isEmpty else { return nil }
        return FeedSnapshot(fetchedAt: .now, items: FeedMerger.merge(pages, limit: Self.limit))
    }
}

enum FeedMerger {
    /// Newest first by parsed age; unknown ages keep their order at the end; duplicates dropped.
    static func merge(_ pages: [[VideoSummary]], limit: Int) -> [VideoSummary] {
        let unique = [VideoSummary]().appendingUnique(pages.flatMap(\.self))
        return unique.enumerated()
            .sorted { lhs, rhs in
                let left = age(of: lhs.element.published ?? "") ?? .infinity
                let right = age(of: rhs.element.published ?? "") ?? .infinity
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .prefix(limit)
            .map(\.element)
    }

    /// Seconds since publishing from YouTube's English relative text ("3 days ago",
    /// "Streamed 2 hours ago"). Requests use `en-US` so this stays parseable.
    static func age(of text: String) -> Double? {
        let words = text.lowercased().split(separator: " ")
        guard words.count >= 3, words.last == "ago",
              let count = Double(words[words.count - 3]) else { return nil }
        let unit = words[words.count - 2].hasSuffix("s") ? words[words.count - 2].dropLast() : words[words.count - 2]
        let seconds: Double? = switch unit {
        case "second": 1
        case "minute": 60
        case "hour": 3600
        case "day": 86400
        case "week": 7 * 86400
        case "month": 30 * 86400
        case "year": 365 * 86400
        default: nil
        }
        return seconds.map { $0 * count }
    }
}

/// Last feed on disk so the Subscriptions tab shows instantly on launch.
public struct FeedCache: Sendable {
    private let file: URL

    public init(directory: URL = URL.cachesDirectory) {
        file = directory.appending(path: "feed.json")
    }

    public func load() -> FeedSnapshot? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(FeedSnapshot.self, from: data)
    }

    public func save(_ snapshot: FeedSnapshot) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
    }
}
