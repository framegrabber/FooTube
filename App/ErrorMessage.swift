import SwiftUI

/// An inline failure: a red warning symbol carries the color so the text stays readable in both
/// appearances. VoiceOver announces it when it appears or changes.
struct ErrorMessage: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
        .onAppear { announce(message) }
        .onChange(of: message) { _, new in announce(new) }
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
