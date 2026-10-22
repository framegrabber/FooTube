import CryptoKit
import Foundation
import os

/// SponsorBlock categories FooTube handles (SPEC success criterion 4).
public enum SponsorCategory: String, CaseIterable, Sendable {
    case sponsor
    case selfpromo
    case interaction
    case intro
    case outro
    case preview
    case musicOfftopic = "music_offtopic"
    case filler

    /// Skipped automatically by default (`SkipSettings.defaultBehavior`): only `sponsor`; every other
    /// category offers a skip button unless changed in Settings.
    public var autoSkips: Bool {
        self == .sponsor
    }
}

public struct SkipSegment: Identifiable, Hashable, Sendable {
    public let id: String
    public let category: SponsorCategory
    public let start: Double
    public let end: Double

    public init(id: String, category: SponsorCategory, start: Double, end: Double) {
        self.id = id
        self.category = category
        self.start = start
        self.end = end
    }
}

/// Reads skip segments from the public SponsorBlock API using the privacy-preserving hash-prefix
/// endpoint: the server only learns the first 4 hex chars of SHA-256(videoID).
/// Docs: https://wiki.sponsor.ajay.app/w/API_Docs (`GET /api/skipSegments/:sha256HashPrefix`).
public struct SponsorBlockClient: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let timeout: Duration
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "sponsorblock")

    public init(
        baseURL: URL = URL(string: "https://sponsor.ajay.app")!,
        session: URLSession = .shared,
        timeout: Duration = .seconds(5),
    ) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    /// Segments for the video, sorted by start. Any failure (network, timeout, 404 = none known,
    /// malformed data) returns an empty list so playback is never blocked.
    public func segments(for videoID: VideoID) async -> [SkipSegment] {
        var request = URLRequest(url: requestURL(for: videoID))
        request.timeoutInterval = Double(timeout.components.seconds)
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let segments = Self.decode(data, for: videoID)
            logger.info("\(videoID, privacy: .public): \(segments.count) segments")
            return segments
        } catch {
            logger.error("\(videoID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func requestURL(for videoID: VideoID) -> URL {
        let categories = "[" + SponsorCategory.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ",") + "]"
        var components = URLComponents(
            url: baseURL.appending(path: "api/skipSegments/\(Self.hashPrefix(for: videoID))"),
            resolvingAgainstBaseURL: false,
        )!
        components.queryItems = [
            URLQueryItem(name: "categories", value: categories),
            URLQueryItem(name: "actionType", value: "skip"),
        ]
        return components.url!
    }

    static func hashPrefix(for videoID: VideoID) -> String {
        SHA256.hash(data: Data(videoID.rawValue.utf8))
            .prefix(2)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func decode(_ data: Data, for videoID: VideoID) -> [SkipSegment] {
        struct VideoEntry: Decodable {
            let videoID: String
            let segments: [Segment]
        }
        struct Segment: Decodable {
            let UUID: String
            let category: String
            let actionType: String
            let segment: [Double]
        }
        guard let entries = try? JSONDecoder().decode([VideoEntry].self, from: data) else { return [] }
        return entries
            .filter { $0.videoID == videoID.rawValue }
            .flatMap(\.segments)
            .compactMap { segment in
                guard segment.actionType == "skip", segment.segment.count == 2,
                      let category = SponsorCategory(rawValue: segment.category),
                      segment.segment[1] > segment.segment[0] else { return nil }
                return SkipSegment(id: segment.UUID, category: category, start: segment.segment[0], end: segment.segment[1])
            }
            .sorted { $0.start < $1.start }
    }
}
