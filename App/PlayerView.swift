import AVKit
import FooTubeCore
import SwiftUI

/// Full-screen system player. Siri Remote transport controls come from `AVPlayerViewController`;
/// SponsorBlock skip buttons use its `contextualActions` (the "Skip Intro"-style button); chapters
/// are the item's navigation markers; "Up next" is the system content proposal at the end.
struct PlayerView: UIViewControllerRepresentable {
    let session: PlayerSession
    /// The user (or the countdown) accepted the Up next proposal.
    let onPlayNext: (VideoSummary) -> Void
    /// The user declined the Up next proposal: the player closes.
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onPlayNext: onPlayNext, onClose: onClose)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = session.player
        controller.delegate = context.coordinator
        context.coordinator.observe(controller)
        context.coordinator.trackOffer(in: controller)
        session.start()
        return controller
    }

    func updateUIViewController(_: AVPlayerViewController, context _: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.session.stop()
        controller.player = nil
    }

    @MainActor
    final class Coordinator: NSObject, @MainActor AVPlayerViewControllerDelegate {
        let session: PlayerSession
        private let onPlayNext: (VideoSummary) -> Void
        private let onClose: () -> Void
        private var observation: NSKeyValueObservation?
        private var shownOffer: SkipSegment?
        /// The proposal is answered once (the countdown and a button press can race).
        private var answeredProposal = false

        init(session: PlayerSession, onPlayNext: @escaping (VideoSummary) -> Void, onClose: @escaping () -> Void) {
            self.session = session
            self.onPlayNext = onPlayNext
            self.onClose = onClose
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

        /// Mirrors `session.offeredSegment` into the controller's contextual actions. Re-registers
        /// observation after every change (Observation's `onChange` fires once).
        func trackOffer(in controller: AVPlayerViewController) {
            let offer = withObservationTracking {
                session.offeredSegment
            } onChange: { [weak self, weak controller] in
                Task { @MainActor in
                    guard let controller else { return }
                    self?.trackOffer(in: controller)
                }
            }
            guard offer != shownOffer else { return }
            shownOffer = offer
            controller.contextualActions = offer.map { segment in
                [UIAction(title: "Skip \(segment.category.displayName)") { [session] _ in session.skipOffered() }]
            } ?? []
        }

        func playerViewController(_ controller: AVPlayerViewController, shouldPresent _: AVContentProposal) -> Bool {
            guard let next = session.upNext else { return false }
            controller.contentProposalViewController = UpNextViewController(video: next)
            return true
        }

        func playerViewController(_: AVPlayerViewController, didAccept _: AVContentProposal) {
            guard !answeredProposal, let next = session.upNext else { return }
            answeredProposal = true
            onPlayNext(next)
        }

        func playerViewController(_: AVPlayerViewController, didReject _: AVContentProposal) {
            guard !answeredProposal else { return }
            answeredProposal = true
            onClose()
        }
    }
}

/// "Up next" screen over the finished video, which shrinks to the top right corner: the proposed
/// video with a countdown, "Play Now" and "Close". Menu also closes.
final class UpNextViewController: AVContentProposalViewController {
    private let video: VideoSummary

    init(video: VideoSummary) {
        self.video = video
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var preferredPlayerViewFrame: CGRect {
        let bounds = view.bounds
        let width = bounds.width * 0.4
        return CGRect(x: bounds.width - width - 80, y: 80, width: width, height: width * 9 / 16)
    }

    /// Built on appearance, when the countdown starts. AVKit's `dateOfAutomaticAcceptance` is not
    /// usable (it reported a date around `distantFuture` in tvOS 26.2), so the countdown runs from
    /// the proposal's `automaticAcceptanceInterval`.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard children.isEmpty else { return }
        let content = UpNextContent(
            video: video,
            preview: contentProposal?.previewImage,
            acceptsAt: contentProposal.flatMap { $0.automaticAcceptanceInterval.isNaN ? nil : Date.now.addingTimeInterval($0.automaticAcceptanceInterval) },
            onPlay: { [weak self] in self?.dismissContentProposal(for: .accept, animated: true) },
            onClose: { [weak self] in self?.dismissContentProposal(for: .reject, animated: true) },
        )
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .menu }) {
            dismissContentProposal(for: .reject, animated: true)
        } else {
            super.pressesBegan(presses, with: event)
        }
    }
}

private struct UpNextContent: View {
    let video: VideoSummary
    let preview: UIImage?
    /// When the countdown plays the video; nil when it doesn't count down.
    let acceptsAt: Date?
    let onPlay: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Up Next").font(.headline).foregroundStyle(.secondary)
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(width: 560, height: 315)
                        .clipShape(.rect(cornerRadius: 16))
                }
                Text(video.title).font(.title3).lineLimit(2)
                if let channel = video.channel?.name {
                    Text(channel).foregroundStyle(.secondary)
                }
                HStack(spacing: 32) {
                    Button(action: onPlay) {
                        if let acceptsAt {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text("Play Now (\(max(0, Int(acceptsAt.timeIntervalSince(context.date).rounded(.up)))))")
                            }
                        } else {
                            Text("Play Now")
                        }
                    }
                    Button("Close", action: onClose)
                }
            }
            .frame(width: 720, alignment: .leading)
            Spacer()
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(.black.opacity(0.6))
        .task {
            // The countdown accepts on its own; AVKit only shows the date.
            guard let acceptsAt else { return }
            try? await Task.sleep(for: .seconds(max(0, acceptsAt.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            onPlay()
        }
    }
}
