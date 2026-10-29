import Foundation
import os

/// Video titles as their uploader wrote them. YouTube translates titles in every list (browse,
/// search, related) into the request language, and no list request can turn that off; only per-video
/// endpoints return the original. Lookup order: oEmbed (about 0.6 KB), then the WEB player's
/// `videoDetails.title` for videos oEmbed can't describe (embedding disabled, live or upcoming).
/// Found titles are kept in memory and in a Caches file (titles rarely change; a purged file only
/// costs lookups); a failed lookup keeps the list's title and is tried again next time.
public actor OriginalTitles {
    public static let shared = OriginalTitles()

    /// Lookups in flight per call; channel pages and the feed (4 channels at a time) stay well under
    /// what YouTube answered without throttling in tests (349 lookups, 32 at a time).
    static let concurrency = 8
    /// Oldest entries are dropped beyond this (about 100 bytes each).
    static let capacity = 3000
    /// The WEB client version InnerTubeKit's list requests use.
    static let webClientVersion = "2.20260213.01.00"

    private let session: URLSession
    private let baseURL: URL
    private let file: URL?
    private let timeout: Duration
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "titles")
    /// Insertion order, oldest first, for eviction; `titles` holds the same keys.
    private var order: [VideoID] = []
    private var titles: [VideoID: String] = [:]
    private var loaded = false

    /// `file` nil keeps titles in memory only.
    public init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://www.youtube.com")!,
        file: URL? = URL.cachesDirectory.appending(path: "original-titles.json"),
        timeout: Duration = .seconds(5),
    ) {
        self.session = session
        self.baseURL = baseURL
        self.file = file
        self.timeout = timeout
    }

    /// `videos` in the same order, each with its original title where one was found.
    public func originals(for videos: [VideoSummary]) async -> [VideoSummary] {
        loadIfNeeded()
        let missing = [VideoID](Set(videos.map(\.id).filter { titles[$0] == nil }))
        if !missing.isEmpty {
            let found = await lookUp(missing)
            for (id, title) in found where titles[id] == nil {
                titles[id] = title
                order.append(id)
            }
            if !found.isEmpty {
                evictAndSave()
            }
        }
        return videos.map { video in titles[video.id].map { video.retitled($0) } ?? video }
    }

    /// Original titles for `ids`, at most `concurrency` lookups at a time; failures are left out.
    private func lookUp(_ ids: [VideoID]) async -> [VideoID: String] {
        let session = session
        let baseURL = baseURL
        let timeout = timeout
        return await withTaskGroup(of: (VideoID, String?).self) { group in
            var pending = ids.makeIterator()
            func enqueue() {
                guard let id = pending.next() else { return }
                group.addTask {
                    await (id, Self.title(of: id, session: session, baseURL: baseURL, timeout: timeout))
                }
            }
            for _ in 0 ..< Self.concurrency {
                enqueue()
            }
            var found: [VideoID: String] = [:]
            for await (id, title) in group {
                if let title {
                    found[id] = title
                } else {
                    logger.debug("no original title for \(id, privacy: .private(mask: .hash))")
                }
                enqueue()
            }
            return found
        }
    }

    private static func title(of id: VideoID, session: URLSession, baseURL: URL, timeout: Duration) async -> String? {
        if let title = await oEmbedTitle(of: id, session: session, baseURL: baseURL, timeout: timeout) {
            return title
        }
        return await playerTitle(of: id, session: session, baseURL: baseURL, timeout: timeout)
    }

    static func oEmbedTitle(of id: VideoID, session: URLSession, baseURL: URL, timeout: Duration) async -> String? {
        var components = URLComponents(url: baseURL.appending(path: "oembed"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(id.rawValue)"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = Double(timeout.components.seconds)
        struct OEmbed: Decodable {
            let title: String?
        }
        return await fetch(request, session: session) { try JSONDecoder().decode(OEmbed.self, from: $0).title }
    }

    static func playerTitle(of id: VideoID, session: URLSession, baseURL: URL, timeout: Duration) async -> String? {
        var components = URLComponents(url: baseURL.appending(path: "youtubei/v1/player"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Double(timeout.components.seconds)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable {
            struct Context: Encodable {
                struct Client: Encodable {
                    let clientName = "WEB"
                    let clientVersion = OriginalTitles.webClientVersion
                    let hl = "en"
                }

                let client = Client()
            }

            let context = Context()
            let videoId: String
        }
        request.httpBody = try? JSONEncoder().encode(Body(videoId: id.rawValue))
        struct Player: Decodable {
            struct Details: Decodable {
                let videoId: String?
                let title: String?
            }

            let videoDetails: Details?
        }
        return await fetch(request, session: session) { data in
            let details = try JSONDecoder().decode(Player.self, from: data).videoDetails
            // Without the matching ID the answer is about another video (or none), not this one.
            return details?.videoId == id.rawValue ? details?.title : nil
        }
    }

    /// `decode` applied to a 200 response; nil for any failure or an empty title.
    private static func fetch(_ request: URLRequest, session: URLSession, decode: (Data) throws -> String?) async -> String? {
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let title = try? decode(data)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        return title
    }

    private struct Entry: Codable {
        let id: VideoID
        let title: String
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let file, let data = try? Data(contentsOf: file),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        for entry in entries where titles[entry.id] == nil {
            titles[entry.id] = entry.title
            order.append(entry.id)
        }
    }

    private func evictAndSave() {
        if order.count > Self.capacity {
            for id in order.prefix(order.count - Self.capacity) {
                titles[id] = nil
            }
            order.removeFirst(order.count - Self.capacity)
        }
        guard let file else { return }
        let entries = order.compactMap { id in titles[id].map { Entry(id: id, title: $0) } }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file, options: .atomic)
        } catch {
            logger.error("Couldn't save original titles: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension VideoSummary {
    /// The same video with another title.
    func retitled(_ title: String) -> VideoSummary {
        VideoSummary(id: id, title: title, channel: channel, duration: duration, viewCount: viewCount, published: published, thumbnail: thumbnail)
    }
}
