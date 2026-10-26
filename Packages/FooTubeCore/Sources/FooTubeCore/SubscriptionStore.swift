import Foundation
import os

/// A subscribed channel.
public struct Subscription: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let avatar: URL?

    public init(id: String, name: String, avatar: URL?) {
        self.id = id
        self.name = name
        self.avatar = avatar
    }

    public var channel: ChannelRef {
        ChannelRef(id: id, name: name)
    }
}

/// Subscriptions kept on this device (and synced to the household's Worker when sync is on). No
/// Google account involved.
///
/// Kept in `UserDefaults` as a `SubscriptionsDocument`: on tvOS that is the persistent local store
/// (up to ~500 KB); files in Application Support or Caches can be purged while the app is not
/// running. A few hundred channels fit comfortably. Unsubscribing leaves a removal marker that the
/// readers hide, so another device's sync can't bring the channel back.
public struct SubscriptionStore: SyncableStore {
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let key = "subscriptions.v2"
    private let legacyKey = "subscriptions.v1"
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "storage")

    /// `now` stamps changes and the one-time migration from `subscriptions.v1`.
    public init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { .now }) {
        self.defaults = defaults
        self.now = now
    }

    /// Alphabetical by name.
    public func channels() -> [Subscription] {
        document().entries
            .filter { $0.removedAt == nil }
            .map(\.subscription)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func isSubscribed(_ channelID: String) -> Bool {
        document().entries.contains { $0.id == channelID && $0.removedAt == nil }
    }

    /// Adds the channel, or refreshes its name/avatar if already subscribed.
    public func subscribe(_ channel: ChannelRef, avatar: URL?) throws {
        var document = document()
        let index = document.entries.firstIndex { $0.id == channel.id }
        let live = index.map { document.entries[$0] }.flatMap { $0.removedAt == nil ? $0 : nil }
        let name = channel.name ?? live?.name ?? channel.id
        let avatar = avatar ?? live?.avatar
        if let live, live.name == name, live.avatar == avatar {
            return
        }
        let record = SubscriptionRecord(id: channel.id, name: name, avatar: avatar, changedAt: SyncCoding.timestamp(now()))
        if let index {
            document.entries[index] = record
        } else {
            document.entries.append(record)
        }
        try save(document)
    }

    /// Turns the subscription into a removal marker.
    public func unsubscribe(_ channelID: String) throws {
        var document = document()
        guard let index = document.entries.firstIndex(where: { $0.id == channelID && $0.removedAt == nil }) else { return }
        let date = SyncCoding.timestamp(now())
        document.entries[index].changedAt = date
        document.entries[index].removedAt = date
        try save(document)
    }

    /// For sync: every entry including removal markers. Migrates `subscriptions.v1` on first use.
    public func document() -> SubscriptionsDocument {
        defaults.syncDocument(SubscriptionsDocument.self, forKey: key, migratingFrom: legacyKey, logger: logger) {
            let date = SyncCoding.timestamp(now())
            let list = defaults.data(forKey: legacyKey).flatMap { try? JSONDecoder().decode([Subscription].self, from: $0) } ?? []
            let records = list.map { SubscriptionRecord(id: $0.id, name: $0.name, avatar: $0.avatar, changedAt: date) }
            return SubscriptionsDocument(entries: records.sorted { $0.id < $1.id })
        }
    }

    /// For sync: saves a merged document as is.
    public func replace(_ document: SubscriptionsDocument) throws(SyncDocumentError) {
        try defaults.setSyncDocument(document, forKey: key)
    }

    private func save(_ document: SubscriptionsDocument) throws(SyncDocumentError) {
        let entries = SyncMerge.withoutExpiredMarkers(document.entries, now: now())
        try replace(SubscriptionsDocument(entries: entries.sorted { $0.id < $1.id }))
    }
}
