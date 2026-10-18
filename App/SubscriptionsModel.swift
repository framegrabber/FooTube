import FooTubeCore
import Foundation
import Observation

/// Observable view of the local subscriptions for SwiftUI.
@MainActor
@Observable
final class SubscriptionsModel {
    private(set) var subscriptions: [Subscription] = []
    private(set) var lastError: String?

    private let store: SubscriptionStore?

    init(store: SubscriptionStore?, error: String? = nil) {
        self.store = store
        lastError = error
        reload()
    }

    func isSubscribed(_ channelID: String) -> Bool {
        subscriptions.contains { $0.id == channelID }
    }

    func toggle(_ channel: ChannelRef, avatar: URL?) {
        guard let store else { return }
        do {
            if isSubscribed(channel.id) {
                try store.unsubscribe(channel.id)
            } else {
                try store.subscribe(channel, avatar: avatar)
            }
            reload()
        } catch {
            lastError = "Couldn't save subscription: \(error.localizedDescription)"
        }
    }

    private func reload() {
        guard let store else { return }
        do {
            subscriptions = try store.channels()
        } catch {
            lastError = "Couldn't load subscriptions: \(error.localizedDescription)"
        }
    }
}
