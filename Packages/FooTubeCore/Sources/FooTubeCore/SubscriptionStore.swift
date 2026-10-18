import Foundation

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

/// Subscriptions stored only on this device. No Google account involved.
///
/// Kept in `UserDefaults` as a small JSON list: on tvOS that is the persistent local store
/// (up to ~500 KB); files in Application Support or Caches can be purged while the app is not
/// running. A few hundred channels fit comfortably.
public struct SubscriptionStore {
    private let defaults: UserDefaults
    private let key = "subscriptions.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Alphabetical by name.
    public func channels() -> [Subscription] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([Subscription].self, from: data) else { return [] }
        return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func isSubscribed(_ channelID: String) -> Bool {
        channels().contains { $0.id == channelID }
    }

    /// Adds the channel, or refreshes its name/avatar if already subscribed.
    public func subscribe(_ channel: ChannelRef, avatar: URL?) throws {
        var list = channels()
        let existing = list.firstIndex { $0.id == channel.id }
        let entry = Subscription(
            id: channel.id,
            name: channel.name ?? existing.map { list[$0].name } ?? channel.id,
            avatar: avatar ?? existing.flatMap { list[$0].avatar },
        )
        if let existing {
            list[existing] = entry
        } else {
            list.append(entry)
        }
        try save(list)
    }

    public func unsubscribe(_ channelID: String) throws {
        try save(channels().filter { $0.id != channelID })
    }

    private func save(_ list: [Subscription]) throws {
        try defaults.set(JSONEncoder().encode(list), forKey: key)
    }
}
