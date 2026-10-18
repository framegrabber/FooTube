import FooTubeCore
import SwiftUI

/// Enter a video ID or YouTube URL and play it.
struct PlayByIDView: View {
    let resolver: any StreamResolver

    @State private var input = ""
    @State private var state: ResolveState = .idle
    @State private var source: PlaybackSource?
    @State private var task: Task<Void, Never>?

    private enum ResolveState: Equatable {
        case idle
        case resolving(VideoID)
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 48) {
            Text(AppInfo.name)
                .font(.largeTitle)

            TextField("Video ID or YouTube URL", text: $input)
                .frame(maxWidth: 1000)
                .onSubmit { play(input) }

            Button("Play") { play(input) }

            status
                .frame(minHeight: 80)
        }
        .padding(80)
        .fullScreenCover(item: $source) { source in
            PlayerView(source: source)
                .ignoresSafeArea()
                .onExitCommand { self.source = nil }
        }
        .task {
            // Debug/test hook: `-play <id or URL>` launch argument (simctl/devicectl launch).
            if let value = UserDefaults.standard.string(forKey: "play") {
                input = value
                play(value)
            }
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
        task?.cancel()
        state = .resolving(id)
        task = Task {
            do throws(ResolveError) {
                let stream = try await resolver.resolve(id)
                guard !Task.isCancelled else { return }
                state = .idle
                source = PlaybackSource(stream: stream)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.message)
            }
        }
    }
}
