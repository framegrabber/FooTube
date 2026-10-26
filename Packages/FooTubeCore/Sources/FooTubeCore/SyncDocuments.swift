import Foundation
import os

/// The stores the sync Worker keeps (Contract: `/v1/stores/:name`); the raw value is the path segment.
public enum SyncStoreName: String, CaseIterable, Hashable, Sendable {
    case subscriptions
    case watchLater
    case history
    case skipSettings
}

/// Why a sync document can't be read or written.
public enum SyncDocumentError: Error, Hashable, Sendable {
    /// Written by a newer FooTube: never merged and never overwritten.
    case unsupportedFormat(Int)
    /// Not JSON, no `format`, or fields missing or of the wrong type.
    case unreadable(detail: String)
    /// A value JSON can't hold, e.g. a non-finite position.
    case unencodable(detail: String)

    public var message: String {
        switch self {
        case let .unsupportedFormat(format): "Sync document has format \(format), newer than this build"
        case let .unreadable(detail): "Sync document unreadable: \(detail)"
        case let .unencodable(detail): "Sync document can't be encoded: \(detail)"
        }
    }
}

/// One store's JSON document, kept the same in `UserDefaults` and on the sync Worker
/// (SPEC-sync-client → Data formats).
public protocol SyncDocument: Codable, Hashable, Sendable {
    static var store: SyncStoreName { get }
    /// The document of a store that was never written.
    static var empty: Self { get }
    var format: Int { get }
    /// `merge(self, remote, lastSyncAt:now:)` from `SyncMerge.swift`.
    func merged(with remote: Self?, lastSyncAt: Date?, now: Date) -> Self
    /// Entries (settings: overrides), removal markers included; for logs.
    var entryCount: Int { get }
}

/// What the sync engine needs from a local store: read its document and replace it with a merged one.
/// Both run on the caller's actor (the main actor in the app), like every other store write.
public protocol SyncableStore {
    associatedtype Document: SyncDocument
    /// The whole document, including removal markers the store's readers hide.
    func document() -> Document
    /// Saves `document` as the store's state; the store's readers see it right away.
    func replace(_ document: Document) throws(SyncDocumentError)
}

/// A subscribed channel, or a removal marker (`removedAt` set) that keeps an unsubscribe from being
/// undone by another device.
public struct SubscriptionRecord: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var avatar: URL?
    public var changedAt: Date
    public var removedAt: Date?

    public init(id: String, name: String, avatar: URL?, changedAt: Date, removedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.changedAt = changedAt
        self.removedAt = removedAt
    }

    public var subscription: Subscription {
        Subscription(id: id, name: name, avatar: avatar)
    }
}

/// `{"format":1, "entries":[SubscriptionRecord]}`, entries ordered by `id`.
public struct SubscriptionsDocument: SyncDocument {
    public static let store = SyncStoreName.subscriptions
    public static let empty = SubscriptionsDocument(entries: [])

    public var format = SyncCoding.format
    public var entries: [SubscriptionRecord]

    public init(entries: [SubscriptionRecord]) {
        self.entries = entries
    }
}

/// A video in Watch Later, or a removal marker (`removedAt` set).
public struct WatchLaterRecord: Codable, Hashable, Sendable {
    public var video: VideoSummary
    /// Orders the list, newest first; set again when a video is re-added.
    public var addedAt: Date
    public var changedAt: Date
    public var removedAt: Date?

    public init(video: VideoSummary, addedAt: Date, changedAt: Date, removedAt: Date? = nil) {
        self.video = video
        self.addedAt = addedAt
        self.changedAt = changedAt
        self.removedAt = removedAt
    }
}

/// `{"format":1, "entries":[WatchLaterRecord]}`, entries ordered newest `addedAt` first.
public struct WatchLaterDocument: SyncDocument {
    public static let store = SyncStoreName.watchLater
    public static let empty = WatchLaterDocument(entries: [])

    public var format = SyncCoding.format
    public var entries: [WatchLaterRecord]

    public init(entries: [WatchLaterRecord]) {
        self.entries = entries
    }
}

/// `{"format":1, "clearedAt"?, "entries":[WatchEntry]}`, entries newest first, at most
/// `WatchHistory.capacity`.
public struct HistoryDocument: SyncDocument {
    public static let store = SyncStoreName.history
    public static let empty = HistoryDocument(entries: [])

    public var format = SyncCoding.format
    /// When History was last cleared; entries updated at or before it are gone on every device.
    public var clearedAt: Date?
    public var entries: [WatchEntry]

    public init(clearedAt: Date? = nil, entries: [WatchEntry]) {
        self.clearedAt = clearedAt
        self.entries = entries
    }
}

/// `{"format":1, "changedAt"?, "overrides":{category: behavior}}`; no `changedAt` means never changed.
/// Raw strings, so categories and behaviors of newer builds pass through a merge unchanged.
public struct SkipSettingsDocument: SyncDocument {
    public static let store = SyncStoreName.skipSettings
    public static let empty = SkipSettingsDocument(changedAt: nil, overrides: [:])

    public var format = SyncCoding.format
    public var changedAt: Date?
    public var overrides: [String: String]

    public init(changedAt: Date?, overrides: [String: String]) {
        self.changedAt = changedAt
        self.overrides = overrides
    }

    /// Stores only differences from the default.
    public init(_ settings: SkipSettings, changedAt: Date?) {
        let pairs = SponsorCategory.allCases.compactMap { category -> (String, String)? in
            let behavior = settings.behavior(for: category)
            return behavior == SkipSettings.defaultBehavior(for: category) ? nil : (category.rawValue, behavior.rawValue)
        }
        self.init(changedAt: changedAt, overrides: Dictionary(uniqueKeysWithValues: pairs))
    }

    /// Unknown categories and behaviors fall back to the default.
    public var settings: SkipSettings {
        let pairs = overrides.compactMap { key, value in
            SponsorCategory(rawValue: key).flatMap { category in SkipBehavior(rawValue: value).map { (category, $0) } }
        }
        return SkipSettings(Dictionary(pairs) { first, _ in first })
    }
}

/// The JSON form of sync documents: ISO 8601 dates with milliseconds in UTC, sorted keys (canonical:
/// equal documents encode to equal bytes, so the bytes serve for tie-breaks and change detection).
public enum SyncCoding {
    /// The newest document format this build reads and writes.
    public static let format = 1

    /// Reads a document after checking its `format`.
    public static func decode<Document: SyncDocument>(_: Document.Type, from data: Data) throws(SyncDocumentError) -> Document {
        let header: FormatHeader
        do {
            header = try JSONDecoder().decode(FormatHeader.self, from: data)
        } catch {
            throw .unreadable(detail: "no format: \(error.localizedDescription)")
        }
        guard header.format <= format else { throw .unsupportedFormat(header.format) }
        guard header.format == format else { throw .unreadable(detail: "format \(header.format)") }
        do {
            return try decoder().decode(Document.self, from: data)
        } catch {
            throw .unreadable(detail: String(describing: error))
        }
    }

    /// The canonical encoding: compare these bytes, not documents, to tell whether a merge changed
    /// anything.
    public static func encode(_ document: some SyncDocument) throws(SyncDocumentError) -> Data {
        try canonical(document)
    }

    /// Dates as stores stamp them: whole milliseconds, rounded down, so a date survives encoding
    /// unchanged and never lies after the moment it was taken.
    public static func timestamp(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
    }

    /// `2026-10-26T21:04:05.123Z`.
    public static func string(from date: Date) -> String {
        let milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
        var (seconds, fraction) = milliseconds.quotientAndRemainder(dividingBy: 1000)
        if fraction < 0 {
            seconds -= 1
            fraction += 1000
        }
        let whole = Date(timeIntervalSince1970: TimeInterval(seconds)).formatted(.iso8601)
        return whole.dropLast() + String(format: ".%03dZ", fraction)
    }

    /// Parses ISO 8601 with or without fractional seconds, to the millisecond.
    public static func date(from string: String) -> Date? {
        let parsed = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string))
            ?? (try? Date.ISO8601FormatStyle().parse(string))
        return parsed.map { Date(timeIntervalSince1970: ($0.timeIntervalSince1970 * 1000).rounded() / 1000) }
    }

    static func canonical(_ value: some Encodable) throws(SyncDocumentError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        do {
            return try encoder.encode(value)
        } catch {
            throw .unencodable(detail: String(describing: error))
        }
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = date(from: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(raw)")
            }
            return date
        }
        return decoder
    }

    private struct FormatHeader: Decodable {
        let format: Int
    }
}

extension UserDefaults {
    /// The document stored under `key`; nil if absent or unreadable.
    func syncDocument<Document: SyncDocument>(_: Document.Type, forKey key: String) -> Document? {
        data(forKey: key).flatMap { try? SyncCoding.decode(Document.self, from: $0) }
    }

    func setSyncDocument(_ document: some SyncDocument, forKey key: String) throws(SyncDocumentError) {
        try set(SyncCoding.encode(document), forKey: key)
    }

    /// The document under `key`, empty if absent or unreadable. While data of the previous format is
    /// stored under `legacyKey`, first moves it over once with `migrate` (unless `key` already holds a
    /// document) and removes `legacyKey`.
    func syncDocument<Document: SyncDocument>(
        _: Document.Type,
        forKey key: String,
        migratingFrom legacyKey: String,
        logger: Logger,
        migrate: () -> Document,
    ) -> Document {
        guard object(forKey: legacyKey) != nil else { return syncDocument(Document.self, forKey: key) ?? .empty }
        let document = syncDocument(Document.self, forKey: key) ?? migrate()
        do {
            try setSyncDocument(document, forKey: key)
            removeObject(forKey: legacyKey)
            logger.info("Migrated \(legacyKey, privacy: .public) to \(key, privacy: .public)")
        } catch {
            logger.error("Couldn't migrate \(legacyKey, privacy: .public): \(error.message, privacy: .public)")
            return document
        }
        return syncDocument(Document.self, forKey: key) ?? document
    }
}

public extension SubscriptionsDocument {
    var entryCount: Int {
        entries.count
    }
}

public extension WatchLaterDocument {
    var entryCount: Int {
        entries.count
    }
}

public extension HistoryDocument {
    var entryCount: Int {
        entries.count
    }
}

public extension SkipSettingsDocument {
    var entryCount: Int {
        overrides.count
    }
}
