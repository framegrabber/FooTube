import FooTubeCore
import SwiftUI

/// Play by ID/URL, plus the MVP test videos.
struct HomeView: View {
    @Environment(PlaybackController.self) private var playback
    @State private var input = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                HStack(spacing: 24) {
                    TextField("Video ID or YouTube URL", text: $input)
                        .frame(maxWidth: 900)
                        .onSubmit(play)
                    Button("Play", action: play)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Test videos")
                        .font(.headline)
                    ForEach(TestVideos.all) { entry in
                        Button {
                            playback.play(entry.id)
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
    }

    private func play() {
        guard let id = VideoID(parsing: input) else {
            playback.fail("Not a YouTube video ID or URL.")
            return
        }
        playback.play(id)
    }
}
