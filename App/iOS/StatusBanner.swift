import FooTubeCore
import SwiftUI

/// "Loading …" while a video resolves, or why it can't play; a small capsule at the top of the screen.
struct StatusBanner: View {
    let status: PlaybackController.Status

    var body: some View {
        Group {
            switch status {
            case .idle:
                EmptyView()
            case let .resolving(title):
                HStack(spacing: 12) {
                    ProgressView()
                    if let title {
                        Text("Loading “\(title)”…")
                    } else {
                        Text("Loading video…")
                    }
                }
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: .capsule)
            case let .failed(message):
                ErrorMessage(message: message)
                    .padding(16)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
        }
        .font(.subheadline)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal)
        .padding(.top, 8)
        .allowsHitTesting(false)
        .animation(.default, value: status)
    }
}
