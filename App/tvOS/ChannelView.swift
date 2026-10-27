import FooTubeCore
import SwiftUI

/// Channel header and its uploads, newest first, with paging.
struct ChannelView: View {
    @State private var model: ChannelModel

    @Environment(SubscriptionsModel.self) private var subscriptions

    init(catalog: any Catalog, channel: ChannelRef) {
        _model = State(initialValue: ChannelModel(catalog: catalog, channel: channel))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                header
                if let error = model.error {
                    ErrorMessage(message: error)
                }
                if model.page == nil, model.error == nil {
                    ProgressView().frame(maxWidth: .infinity)
                }
                // All uploads belong to this channel, so no "Open channel" menu here.
                VideoGrid(videos: model.videos, onReachEnd: model.loadMore)
                if model.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(80)
        }
        .scrollClipDisabled() // focused cards lift past the edges
        .task(id: model.channel.id) { await model.load() }
    }

    /// A full-width focus section, so pressing up from any first-row card lands on Subscribe.
    private var header: some View {
        HStack(spacing: 32) {
            RemoteImage(url: model.page?.avatar, size: CGSize(width: 160, height: 160))
                .frame(width: 160, height: 160)
                .clipShape(.circle)
            VStack(alignment: .leading, spacing: 12) {
                Text(model.name ?? String(localized: "Channel"))
                    .font(.title2)
                if let subscribers = model.page?.subscriberCount {
                    Text(subscribers)
                        .foregroundStyle(.secondary)
                }
                Button(subscriptions.isSubscribed(model.channel.id) ? LocalizedStringKey("Unsubscribe") : LocalizedStringKey("Subscribe")) {
                    subscriptions.toggle(model.page?.channel ?? model.channel, avatar: model.page?.avatar)
                }
                .disabled(model.page == nil) // wait for the real name and avatar
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}
