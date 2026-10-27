import FooTubeCore
import SwiftUI

/// The Sync status row's value.
struct SyncStateText: View {
    let state: SyncModel.State

    var body: some View {
        switch state {
        case .off: Text("Off")
        case .syncing: Text("Syncing…")
        case let .synced(date):
            // Refreshes the relative time while Settings stays open.
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text("Synced \(date, format: .relative(presentation: .named))")
            }
        case .offline: Text("Offline, will retry")
        case .failed: Text("Sync failed, will retry")
        case .tokenRejected: Text("Token rejected")
        case .updateRequired: Text("Update FooTube on this device")
        }
    }
}

/// Version and expiry of this install, for Settings → About.
enum AppInstall {
    static let version: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }()

    /// When this install stops launching; nil in the Simulator, which embeds no profile.
    static let expiry: Date? = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap(ProvisioningProfile.expirationDate(in:))
}

/// Projects FooTube is built on, with their licenses.
enum Credit: CaseIterable {
    case youTubeKit, innerTubeKit, sponsorBlock

    var name: String {
        switch self {
        case .youTubeKit: "YouTubeKit"
        case .innerTubeKit: "InnerTubeKit"
        case .sponsorBlock: "SponsorBlock"
        }
    }

    var license: String {
        switch self {
        case .youTubeKit, .innerTubeKit: "MIT"
        case .sponsorBlock: "CC BY-NC-SA 4.0"
        }
    }

    var text: String {
        switch self {
        case .youTubeKit:
            #if os(tvOS)
                String(localized: "Finds the video streams on this Apple TV. github.com/alexeichhorn/YouTubeKit, MIT License.")
            #else
                String(localized: "Finds the video streams on this device. github.com/alexeichhorn/YouTubeKit, MIT License.")
            #endif
        case .innerTubeKit:
            String(localized: "Search, channels, chapters and related videos. A renamed copy of github.com/b5i/YouTubeKit, MIT License.")
        case .sponsorBlock:
            String(localized: "Segment data by the SponsorBlock community, sponsor.ajay.app, licensed CC BY-NC-SA 4.0. FooTube asks for segments by the first four characters of a hash of the video ID, so SponsorBlock never receives the video ID itself.")
        }
    }
}
