import FooTubeCore
import SwiftUI

/// Home: play by ID/URL, plus the MVP test videos.
struct HomeView: View {
    let resolver: any StreamResolver
    let sponsorBlock: SponsorBlockClient

    @State private var input = ""
    @State private var state: ResolveState = .idle
    @State private var session: PlayerSession?
    @State private var didAutoplay = false
    @State private var task: Task<Void, Never>?

    private enum ResolveState: Equatable {
        case idle
        case resolving(VideoID)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                Text(AppInfo.name)
                    .font(.largeTitle)

                HStack(spacing: 24) {
                    TextField("Video ID or YouTube URL", text: $input)
                        .frame(maxWidth: 900)
                        .onSubmit { play(input) }
                    Button("Play") { play(input) }
                }

                status
                    .frame(minHeight: 60)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Test videos")
                        .font(.headline)
                    ForEach(TestVideos.all) { entry in
                        Button {
                            play(entry.id)
                        } label: {
                            HStack {
                                Text(entry.label)
                                Spacer()
                                Text(entry.id.rawValue)
                                    .foregroundStyle(.secondary)
                                    .monospaced()
                            }
                            .frame(maxWidth: 1100)
                        }
                    }
                }
            }
            .padding(80)
        }
        .fullScreenCover(item: $session) { session in
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
                .onExitCommand { self.session = nil }
        }
        .task {
            // Debug/test hook: `-play <id or URL>` launch argument (simctl/devicectl launch). Once per launch.
            guard !didAutoplay, let value = UserDefaults.standard.string(forKey: "play") else { return }
            didAutoplay = true
            input = value
            play(value)
        }
    }

    @ViewBuilder private var status: some View {
        switch state {
        case .idle:
            EmptyView()
        case let .resolving(id):
            HStack(spacing: 24) {
                ProgressView()
                Text("Resolving \(id.rawValue)…")
            }
        case let .failed(message):
            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private func play(_ text: String) {
        guard let id = VideoID(parsing: text) else {
            state = .failed("Not a YouTube video ID or URL.")
            return
        }
        play(id)
    }

    private func play(_ id: VideoID) {
        let requestedAt = ContinuousClock.now
        task?.cancel()
        state = .resolving(id)
        task = Task {
            do throws(ResolveError) {
                let stream = try await resolver.resolve(id)
                guard !Task.isCancelled else { return }
                state = .idle
                session = PlayerSession(
                    source: PlaybackSource(stream: stream),
                    sponsorBlock: sponsorBlock,
                    requestedAt: requestedAt,
                )
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.message)
            }
        }
    }
}
