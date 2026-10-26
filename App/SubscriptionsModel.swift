import FooTubeCore
import Foundation
import Observation

/// Observable view of the local subscriptions for SwiftUI.
@MainActor
@Observable
final class SubscriptionsModel {
    private(set) var subscriptions: [Subscription] = []
    private(set) var lastError: String?

    /// Called after this model changed the store (`SyncModel` schedules a round).
    @ObservationIgnored var onLocalChange: (@MainActor () -> Void)?

    private let store: SubscriptionStore

    init(store: SubscriptionStore) {
        self.store = store
        subscriptions = store.channels()
    }

    /// Reads the store again after sync merged other devices' changes into it.
    func reload() {
        subscriptions = store.channels()
    }

    func isSubscribed(_ channelID: String) -> Bool {
        subscriptions.contains { $0.id == channelID }
    }

    func toggle(_ channel: ChannelRef, avatar: URL?) {
        do {
            if isSubscribed(channel.id) {
                try store.unsubscribe(channel.id)
            } else {
                try store.subscribe(channel, avatar: avatar)
            }
            subscriptions = store.channels()
            lastError = nil
            onLocalChange?()
        } catch {
            lastError = String(localized: "Couldn't save subscription: \(error.localizedDescription)")
        }
    }
}
