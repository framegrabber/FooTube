import AVKit
import FooTubeCore
import SwiftUI

/// Full-screen system player for a resolved stream. Siri Remote transport controls come from
/// `AVPlayerViewController`.
struct PlayerView: UIViewControllerRepresentable {
    let source: PlaybackSource

    func makeUIViewController(context _: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(playerItem: AVPlayerItem(asset: source.asset))
        controller.player = player
        player.play()
        return controller
    }

    func updateUIViewController(_: AVPlayerViewController, context _: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator _: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}
