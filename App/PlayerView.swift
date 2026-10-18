import AVKit
import FooTubeCore
import SwiftUI

/// Full-screen system player. Siri Remote transport controls come from `AVPlayerViewController`.
struct PlayerView: UIViewControllerRepresentable {
    let session: PlayerSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = session.player
        context.coordinator.observe(controller)
        session.start()
        return controller
    }

    func updateUIViewController(_: AVPlayerViewController, context _: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.session.stop()
        controller.player = nil
    }

    @MainActor
    final class Coordinator {
        let session: PlayerSession
        private var observation: NSKeyValueObservation?

        init(session: PlayerSession) {
            self.session = session
        }

        func observe(_ controller: AVPlayerViewController) {
            observation = controller.observe(\.isReadyForDisplay, options: [.initial, .new]) { [session] controller, _ in
                MainActor.assumeIsolated {
                    if controller.isReadyForDisplay {
                        session.firstFrameShown()
                    }
                }
            }
        }
    }
}

/// Small corner readout: resolved source, current variant, bitrate, dropped frames, time to first frame.
struct DiagnosticsOverlay: View {
    let session: PlayerSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.source.stream.summary)
            Text("Now \(session.presentationHeight, format: .number.grouping(.never))p · \(session.indicatedBitrate / 1_000_000, format: .number.precision(.fractionLength(1))) Mbps · \(session.droppedFrames) dropped")
            if let ttff = session.timeToFirstFrame {
                Text("First frame \(ttff.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))")
            }
        }
        .font(.caption2.monospacedDigit())
        .padding(16)
        .background(.black.opacity(0.6), in: .rect(cornerRadius: 12))
        .padding(40)
        .allowsHitTesting(false)
    }
}
