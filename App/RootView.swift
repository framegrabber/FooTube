import FooTubeCore
import SwiftUI

/// Tabs plus the shared full-screen player and resolve/failure banner.
struct RootView: View {
    let catalog: any Catalog
    @State var playback: PlaybackController
    @State private var didAutoplay = false

    var body: some View {
        TabView {
            Tab("Search", systemImage: "magnifyingglass") {
                SearchView(catalog: catalog)
            }
            Tab("Play", systemImage: "play.rectangle") {
                HomeView()
            }
        }
        .environment(playback)
        .overlay(alignment: .bottom) {
            StatusBanner(status: playback.status)
        }
        .fullScreenCover(item: $playback.session) { session in
            PlayerView(session: session)
                .ignoresSafeArea()
                .overlay(alignment: .topLeading) {
                    #if DEBUG
                        DiagnosticsOverlay(session: session)
                    #endif
                }
                .overlay(alignment: .bottomLeading) {
                    if let notice = session.notice {
                        Text(notice)
                            .font(.callout)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.black.opacity(0.7), in: .capsule)
                            .padding(60)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .onExitCommand { playback.session = nil }
        }
        .task {
            // Debug/test hook: `-play <id or URL>` launch argument (simctl/devicectl launch). Once per launch.
            guard !didAutoplay, let value = UserDefaults.standard.string(forKey: "play") else { return }
            didAutoplay = true
            if let id = VideoID(parsing: value) {
                playback.play(id)
            }
        }
    }
}

private struct StatusBanner: View {
    let status: PlaybackController.Status

    var body: some View {
        Group {
            switch status {
            case .idle:
                EmptyView()
            case let .resolving(id):
                HStack(spacing: 24) {
                    ProgressView()
                    Text("Loading \(id.rawValue)…")
                }
                .padding(24)
                .background(.regularMaterial, in: .capsule)
            case let .failed(message):
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .background(.regularMaterial, in: .rect(cornerRadius: 20))
            }
        }
        .padding(.bottom, 40)
        .allowsHitTesting(false)
    }
}
