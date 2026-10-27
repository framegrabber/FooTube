import AVKit
import FooTubeCore
import SwiftUI
import UIKit

/// SwiftUI over the full-screen player. AVKit on iOS has no contextual actions (Skip button) and no
/// chapter markers, so FooTube adds its own: the skip notice between video and controls, and a Skip
/// button and a Chapters button at the top trailing edge, below AVKit's top row of controls (its
/// bottom edge holds the transport bar and the playback speed, More and subtitle buttons).
enum PlayerOverlay {
    @MainActor
    static func install(in controller: AVPlayerViewController, session: PlayerSession) {
        // The notice never takes touches: it sits under AVKit's controls and fills the video area.
        if let overlay = controller.contentOverlayView {
            let notice = UIHostingController(rootView: SkipNotice(session: session))
            notice.view.backgroundColor = .clear
            notice.view.isUserInteractionEnabled = false
            controller.addChild(notice)
            notice.view.frame = overlay.bounds
            notice.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.addSubview(notice.view)
            notice.didMove(toParent: controller)
        }

        // The buttons sit above AVKit's views and are only as large as they are, so every other
        // touch reaches AVKit's controls.
        let chrome = PlayerChrome(player: session.player)
        let actions = UIHostingController(rootView: PlayerActions(session: session, chrome: chrome))
        actions.sizingOptions = .intrinsicContentSize
        actions.view.backgroundColor = .clear
        controller.addChild(actions)
        controller.view.addSubview(actions.view)
        actions.view.translatesAutoresizingMaskIntoConstraints = false
        let guide = controller.view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            actions.view.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            actions.view.topAnchor.constraint(equalTo: guide.topAnchor, constant: 64),
        ])
        actions.didMove(toParent: controller)
        chrome.observeTouches(in: controller.view)
    }
}

/// Whether the Chapters button shows: like AVKit's controls, after a touch on the player and while
/// paused; hidden a few seconds after the last touch while playing.
@MainActor
@Observable
final class PlayerChrome: NSObject, UIGestureRecognizerDelegate {
    private(set) var isVisible = true

    @ObservationIgnored private let player: AVPlayer
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    init(player: AVPlayer) {
        self.player = player
        super.init()
        scheduleHide()
    }

    func observeTouches(in view: UIView) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(touched))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    @objc private func touched() {
        isVisible = true
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, let self else { return }
                if player.timeControlStatus == .playing {
                    isVisible = false
                    return
                }
            }
        }
    }

    nonisolated func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
        true
    }
}

/// "Sponsor skipped" for a few seconds after an automatic skip, top left.
private struct SkipNotice: View {
    let session: PlayerSession

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let notice = session.notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.7), in: .capsule)
                    .padding(.top, 72)
                    .padding(.leading, 16)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: session.notice)
    }
}

/// Skip button for an offered segment and the Chapters button.
private struct PlayerActions: View {
    let session: PlayerSession
    let chrome: PlayerChrome

    @State private var showsChapters = false

    var body: some View {
        HStack(spacing: 12) {
            if chrome.isVisible, !session.chapters.isEmpty {
                Button("Chapters", systemImage: "list.bullet") {
                    showsChapters = true
                }
                .transition(.opacity)
            }
            if let segment = session.offeredSegment {
                Button("Skip \(segment.category.localizedName)", systemImage: "forward.fill") {
                    session.skipOffered()
                }
                .transition(.opacity)
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(.white)
        .environment(\.colorScheme, .dark) // over video whatever the system appearance
        .animation(.easeOut(duration: 0.25), value: chrome.isVisible)
        .animation(.easeOut(duration: 0.25), value: session.offeredSegment)
        .sheet(isPresented: $showsChapters) {
            ChapterList(session: session)
                .presentationDetents([.medium, .large])
        }
    }
}

/// The video's chapters with their thumbnails and start times; the current one is marked, tapping
/// one plays from there.
private struct ChapterList: View {
    let session: PlayerSession

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var thumbnailWidth: CGFloat = 96

    var body: some View {
        let current = session.chapters.last { $0.start <= session.position }
        NavigationStack {
            List(session.chapters, id: \.start) { chapter in
                Button {
                    session.seek(to: chapter)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        RemoteImage(url: chapter.thumbnail, size: CGSize(width: thumbnailWidth, height: thumbnailWidth * 9 / 16))
                            .frame(width: thumbnailWidth, height: thumbnailWidth * 9 / 16)
                            .clipShape(.rect(cornerRadius: 6))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chapter.title)
                                .fontWeight(chapter == current ? .semibold : .regular)
                            Text(Duration.seconds(chapter.start), format: .time(pattern: chapter.start >= 3600 ? .hourMinuteSecond : .minuteSecond))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if chapter == current {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.tint)
                                .accessibilityLabel(Text("Now playing"))
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
