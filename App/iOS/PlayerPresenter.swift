import AVFoundation
import AVKit
import FooTubeCore
import os
import SwiftUI
import UIKit

/// Invisible view in the root view that presents the current session's player.
struct PlayerHost: UIViewControllerRepresentable {
    let playback: PlaybackController
    /// The session to show; nil dismisses the player.
    let session: PlayerSession?

    func makeCoordinator() -> PlayerPresenter {
        PlayerPresenter(playback: playback)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.isUserInteractionEnabled = false
        context.coordinator.host = host
        return host
    }

    func updateUIViewController(_: UIViewController, context: Context) {
        context.coordinator.show(session)
    }
}

/// Presents a session full screen in `AVPlayerViewController`, modally from UIKit as AVKit expects:
/// Picture in Picture dismisses the presented player and the restore button presents it again.
/// Closing the player (its close button or a swipe down) or Picture in Picture ends the session.
/// Over the video: a notice after an automatic skip, a Skip button for offered segments and a
/// Chapters button that opens the chapter list (AVKit on iOS shows no chapter markers).
@MainActor
final class PlayerPresenter: NSObject, @MainActor AVPlayerViewControllerDelegate {
    weak var host: UIViewController?

    private let playback: PlaybackController
    private var session: PlayerSession?
    private var controller: AVPlayerViewController?
    private var readyObservation: NSKeyValueObservation?
    /// Between Picture in Picture's start and its end; the dismissal it causes doesn't end the session.
    private var isInPictureInPicture = false
    /// The user asked to return from Picture in Picture to the full-screen player.
    private var isRestoring = false
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "playback")

    init(playback: PlaybackController) {
        self.playback = playback
    }

    func show(_ next: PlayerSession?) {
        guard next !== session else { return }
        tearDown()
        session = next
        guard let next, let host else { return }
        activateAudioSession()
        let controller = AVPlayerViewController()
        controller.player = next.player
        controller.delegate = self
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.modalPresentationStyle = .fullScreen
        controller.view.accessibilityIdentifier = "player" // UI tests
        if let title = next.title {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierTitle
            item.value = title as NSString
            item.extendedLanguageTag = "und"
            next.player.currentItem?.externalMetadata = [item]
        }
        PlayerOverlay.install(in: controller, session: next)
        readyObservation = controller.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak next] controller, _ in
            MainActor.assumeIsolated {
                if controller.isReadyForDisplay {
                    next?.firstFrameShown()
                }
            }
        }
        self.controller = controller
        next.start()
        Self.topmost(from: host).present(controller, animated: true)
    }

    /// Stops the previous session's player and takes it off screen (also out of Picture in Picture).
    private func tearDown() {
        guard let controller else { return }
        controller.delegate = nil
        readyObservation = nil
        session?.stop()
        controller.player = nil
        if controller.presentingViewController != nil {
            controller.dismiss(animated: true)
        }
        self.controller = nil
        isInPictureInPicture = false
        isRestoring = false
    }

    /// `.playback`: sound with the silent switch on, and Picture in Picture keeps playing in the background.
    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.error("Audio session not activated: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func close() {
        // Ends the session; `show(nil)` then tears the player down.
        playback.session = nil
    }

    private static func topmost(from controller: UIViewController) -> UIViewController {
        var top = controller
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    // MARK: AVPlayerViewControllerDelegate

    func playerViewController(_ controller: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: nil) { [weak self] context in
            guard let self, !context.isCancelled, controller === self.controller, !isInPictureInPicture else { return }
            close()
        }
    }

    func playerViewControllerWillStartPictureInPicture(_ controller: AVPlayerViewController) {
        guard controller === self.controller else { return }
        isInPictureInPicture = true
        let id = session?.id.rawValue ?? ""
        logger.info("\(id, privacy: .public) Picture in Picture started")
    }

    func playerViewController(_ controller: AVPlayerViewController, failedToStartPictureInPictureWithError error: any Error) {
        guard controller === self.controller else { return }
        isInPictureInPicture = false
        logger.error("Picture in Picture failed: \(error.localizedDescription, privacy: .public)")
    }

    func playerViewController(
        _ controller: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void,
    ) {
        guard controller === self.controller, let host, controller.presentingViewController == nil else {
            completionHandler(controller === self.controller)
            return
        }
        isRestoring = true
        Self.topmost(from: host).present(controller, animated: true) {
            completionHandler(true)
        }
    }

    func playerViewControllerDidStopPictureInPicture(_ controller: AVPlayerViewController) {
        guard controller === self.controller else { return }
        isInPictureInPicture = false
        if isRestoring {
            isRestoring = false
        } else {
            close() // closed from the Picture in Picture window
        }
    }
}
