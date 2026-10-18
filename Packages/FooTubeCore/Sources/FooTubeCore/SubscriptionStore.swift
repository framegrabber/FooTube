import Foundation
import SwiftData

/// A subscribed channel as the UI sees it (value type, safe to pass around).
public struct Subscription: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let avatar: URL?

    public var channel: ChannelRef {
        ChannelRef(id: id, name: name)
    }
}

@Model
final class SubscribedChannel {
    @Attribute(.unique) var channelID: String
    var name: String
    var avatarURL: URL?
    var subscribedAt: Date

    init(channelID: String, name: String, avatarURL: URL?, subscribedAt: Date) {
        self.channelID = channelID
        self.name = name
        self.avatarURL = avatarURL
        self.subscribedAt = subscribedAt
    }
}

/// Subscriptions stored only on this device (SwiftData). No Google account involved.
@MainActor
public final class SubscriptionStore {
    private let container: ModelContainer
    private var context: ModelContext {
        container.mainContext
    }

    /// Default on-disk store in Application Support.
    public convenience init() throws {
        try self.init(configuration: ModelConfiguration("Subscriptions"))
    }

    public convenience init(url: URL) throws {
        try self.init(configuration: ModelConfiguration(url: url))
    }

    public convenience init(inMemory: Bool) throws {
        try self.init(configuration: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    private init(configuration: ModelConfiguration) throws {
        container = try ModelContainer(for: SubscribedChannel.self, configurations: configuration)
    }

    public func channels() throws -> [Subscription] {
        try context.fetch(FetchDescriptor<SubscribedChannel>(sortBy: [SortDescriptor(\.name)]))
            .map { Subscription(id: $0.channelID, name: $0.name, avatar: $0.avatarURL) }
    }

    public func isSubscribed(_ channelID: String) throws -> Bool {
        try existing(channelID) != nil
    }

    /// Adds the channel, or refreshes its name/avatar if already subscribed.
    public func subscribe(_ channel: ChannelRef, avatar: URL?) throws {
        if let entry = try existing(channel.id) {
            entry.name = channel.name ?? entry.name
            entry.avatarURL = avatar ?? entry.avatarURL
        } else {
            context.insert(SubscribedChannel(channelID: channel.id, name: channel.name ?? channel.id, avatarURL: avatar, subscribedAt: .now))
        }
        try context.save()
    }

    public func unsubscribe(_ channelID: String) throws {
        if let entry = try existing(channelID) {
            context.delete(entry)
            try context.save()
        }
    }

    private func existing(_ channelID: String) throws -> SubscribedChannel? {
        var descriptor = FetchDescriptor<SubscribedChannel>(predicate: #Predicate { $0.channelID == channelID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
