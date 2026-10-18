import FooTubeCore
import SwiftUI

/// Subscribed channels (stored on this device); selecting one opens its channel page.
struct SubscriptionsView: View {
    let catalog: any Catalog

    @Environment(SubscriptionsModel.self) private var subscriptions
    @State private var path: [ChannelRef] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 6)

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    if let error = subscriptions.lastError {
                        Text(error).foregroundStyle(.red)
                    }
                    if subscriptions.subscriptions.isEmpty {
                        Text("No subscriptions yet. Open a channel from search (long-press a video) and choose Subscribe.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Channels").font(.headline)
                        LazyVGrid(columns: columns, spacing: 40) {
                            ForEach(subscriptions.subscriptions) { subscription in
                                Button {
                                    path.append(subscription.channel)
                                } label: {
                                    ChannelTile(subscription: subscription)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .padding(80)
            }
            .navigationDestination(for: ChannelRef.self) { channel in
                ChannelView(catalog: catalog, channel: channel, onOpenChannel: { path.append($0) })
            }
        }
    }
}

private struct ChannelTile: View {
    let subscription: Subscription

    var body: some View {
        VStack(spacing: 12) {
            AsyncImage(url: subscription.avatar) { image in
                image.resizable()
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 160, height: 160)
            .clipShape(.circle)
            Text(subscription.name)
                .font(.caption)
                .lineLimit(1)
        }
    }
}
