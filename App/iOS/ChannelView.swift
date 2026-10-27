import FooTubeCore
import SwiftUI

/// Channel header with Subscribe, then its uploads, newest first, with paging.
struct ChannelView: View {
    @State private var model: ChannelModel

    @Environment(SubscriptionsModel.self) private var subscriptions
    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 80

    init(catalog: any Catalog, channel: ChannelRef) {
        _model = State(initialValue: ChannelModel(catalog: catalog, channel: channel))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
            .padding()
        }
        .navigationTitle(model.name ?? String(localized: "Channel"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            RemoteImage(url: model.page?.avatar, size: CGSize(width: avatarSize, height: avatarSize))
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(.circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.name ?? String(localized: "Channel"))
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                if let subscribers = model.page?.subscriberCount {
                    Text(subscribers)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                subscribeButton
                    .disabled(model.page == nil) // wait for the real name and avatar
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var subscribeButton: some View {
        let toggle = { subscriptions.toggle(model.page?.channel ?? model.channel, avatar: model.page?.avatar) }
        if subscriptions.isSubscribed(model.channel.id) {
            Button("Unsubscribe", action: toggle)
                .buttonStyle(.bordered)
        } else {
            Button("Subscribe", action: toggle)
                .buttonStyle(.borderedProminent)
        }
    }
}
