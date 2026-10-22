import FooTubeCore
import SwiftUI

/// Settings tab laid out like the Apple TV's own Settings: a centred page title, the app's artwork
/// on the left with a short description of the focused row under it, grouped rows on the right.
/// SponsorBlock categories open a page with their three behaviors; the tab owner holds `path` so
/// returning from the tab bar goes back to the first page.
struct SettingsView: View {
    @Binding var path: [SponsorCategory]

    var body: some View {
        NavigationStack(path: $path) {
            SettingsPage()
                .navigationDestination(for: SponsorCategory.self) { category in
                    SkipBehaviorPage(category: category)
                }
        }
    }
}

private struct SettingsPage: View {
    enum Row: Hashable {
        case category(SponsorCategory)
        case restoreDefaults
        case clearHistory
        case clearWatchLater
        case version
        case expiry
        case credit(Credit)
    }

    private enum Confirmation: Identifiable {
        case history, watchLater
        var id: Self {
            self
        }
    }

    @Environment(SettingsModel.self) private var settings
    @Environment(WatchHistoryModel.self) private var watchHistory
    @Environment(WatchLaterModel.self) private var watchLater
    @FocusState private var focus: Row?
    /// The description keeps the last row while focus is in the tab bar.
    @State private var described: Row = .category(.sponsor)
    @State private var confirmation: Confirmation?

    var body: some View {
        SettingsLayout(title: String(localized: "Settings"), description: description(of: described)) {
            Section("SponsorBlock") {
                ForEach(SponsorCategory.allCases, id: \.self) { category in
                    NavigationLink(value: category) {
                        LabeledContent(category.localizedName, value: settings.skip.behavior(for: category).localizedName)
                    }
                    .focused($focus, equals: .category(category))
                }
                Button("Restore Defaults") { settings.restoreDefaults() }
                    .disabled(settings.skip.isDefault)
                    .focused($focus, equals: .restoreDefaults)
            }
            Section("History") {
                Button { confirmation = .history } label: {
                    LabeledContent("Clear Watch History") { Text("\(watchHistory.count) videos") }
                }
                .disabled(watchHistory.count == 0)
                .focused($focus, equals: .clearHistory)
                Button { confirmation = .watchLater } label: {
                    LabeledContent("Clear Watch Later") { Text("\(watchLater.items.count) videos") }
                }
                .disabled(watchLater.items.isEmpty)
                .focused($focus, equals: .clearWatchLater)
            }
            Section("About") {
                // Information rows are buttons without an action so they take focus and get a
                // description, like the Info rows of the Apple TV's own Settings.
                Button {} label: { LabeledContent("Version", value: Self.version) }
                    .focused($focus, equals: .version)
                if let expiry = Self.expiry {
                    Button {} label: {
                        LabeledContent("Expires") { Text(expiry, format: .relative(presentation: .named)) }
                    }
                    .focused($focus, equals: .expiry)
                }
                ForEach(Credit.allCases, id: \.self) { credit in
                    Button {} label: { LabeledContent(credit.name, value: credit.license) }
                        .focused($focus, equals: .credit(credit))
                }
            }
        }
        .onChange(of: focus) { _, row in
            if let row {
                described = row
            }
        }
        .confirmationDialog(
            confirmation == .history ? "Clear watch history?" : "Clear Watch Later?",
            isPresented: Binding(get: { confirmation != nil }, set: {
                if !$0 {
                    confirmation = nil
                }
            }),
            titleVisibility: .visible,
            presenting: confirmation,
        ) { confirmed in
            switch confirmed {
            case .history:
                Button("Clear Watch History", role: .destructive) { watchHistory.clear() }
            case .watchLater:
                Button("Clear Watch Later", role: .destructive) { watchLater.clear() }
            }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private func description(of row: Row) -> SettingsDescription {
        switch row {
        case let .category(category):
            SettingsDescription(text: category.localizedDescription)
        case .restoreDefaults:
            SettingsDescription(text: String(localized: "By default, sponsor segments are skipped automatically and every other category shows a Skip button."))
        case .clearHistory:
            SettingsDescription(text: String(localized: "Clearing removes every video from History, with its resume position and watched mark. Subscriptions and Watch Later stay."))
        case .clearWatchLater:
            SettingsDescription(text: String(localized: "Clearing removes every saved video from Watch Later. History and subscriptions stay."))
        case .version:
            SettingsDescription(text: String(localized: "Plays YouTube without ads: streams are found on this Apple TV and play in Apple's player. Subscriptions, history and Watch Later stay on this Apple TV. Not affiliated with YouTube or Google; using YouTube this way is against its Terms of Service."))
        case .expiry:
            SettingsDescription(text: Self.expiry.map { String(localized: "This install stops launching on \($0.formatted(date: .long, time: .shortened)). Run scripts/run-device.sh again to renew it; subscriptions, history and Watch Later stay.") } ?? "")
        case let .credit(credit):
            SettingsDescription(text: credit.text)
        }
    }

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }()

    /// When this install stops launching; nil in the Simulator, which embeds no profile.
    private static let expiry: Date? = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap(ProvisioningProfile.expirationDate(in:))
}

/// The three behaviors of one SponsorBlock category, titled with the category; the description
/// explains the category and the focused behavior.
private struct SkipBehaviorPage: View {
    let category: SponsorCategory

    @Environment(SettingsModel.self) private var settings
    @FocusState private var focus: SkipBehavior?
    @State private var described: SkipBehavior?

    var body: some View {
        let current = settings.skip.behavior(for: category)
        SettingsLayout(
            title: category.localizedName,
            description: SettingsDescription(text: category.localizedDescription, detail: (described ?? current).explanation),
        ) {
            Section {
                ForEach(SkipBehavior.allCases, id: \.self) { behavior in
                    Button {
                        settings.setBehavior(behavior, for: category)
                    } label: {
                        HStack {
                            Text(behavior.localizedName)
                            Spacer()
                            if behavior == current {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .focused($focus, equals: behavior)
                }
            }
        }
        .defaultFocus($focus, current)
        .onChange(of: focus) { _, behavior in
            if let behavior {
                described = behavior
            }
        }
    }
}

/// What the left column says about the focused row.
private struct SettingsDescription: Hashable {
    let text: String
    /// Second paragraph, e.g. what the focused option does.
    var detail: String?
}

/// Artwork and description left, grouped rows right, page title centred above.
private struct SettingsLayout<Rows: View>: View {
    let title: String
    let description: SettingsDescription
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(spacing: 40) {
            // Part of the page rather than `navigationTitle`, which floats over the list as it scrolls.
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 100) {
                VStack(spacing: 48) {
                    Image("AppArtwork")
                        .resizable()
                        .aspectRatio(5 / 3, contentMode: .fit)
                        .frame(width: 520)
                        .clipShape(.rect(cornerRadius: 28))
                        .accessibilityHidden(true)
                    // Fixed height, so the artwork stays put while the text changes.
                    ZStack(alignment: .top) {
                        DescriptionText(description: description)
                            .id(description)
                            .transition(.opacity)
                    }
                    .frame(height: 300, alignment: .top)
                    .animation(.easeOut(duration: 0.2), value: description)
                }
                .frame(width: 620)
                .frame(maxHeight: .infinity)
                List {
                    rows
                }
                .listStyle(.grouped)
            }
        }
        .padding(.horizontal, 80)
    }
}

private struct DescriptionText: View {
    let description: SettingsDescription

    var body: some View {
        VStack(spacing: 20) {
            Text(description.text)
                .foregroundStyle(.secondary)
            if let detail = description.detail {
                Text(detail)
            }
        }
        .font(.callout)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// Projects FooTube is built on, with their licenses.
private enum Credit: CaseIterable {
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
            String(localized: "Finds the video streams on this Apple TV. github.com/alexeichhorn/YouTubeKit, MIT License.")
        case .innerTubeKit:
            String(localized: "Search, channels, chapters and related videos. A renamed copy of github.com/b5i/YouTubeKit, MIT License.")
        case .sponsorBlock:
            String(localized: "Segment data by the SponsorBlock community, sponsor.ajay.app, licensed CC BY-NC-SA 4.0. FooTube asks for segments by the first four characters of a hash of the video ID, so SponsorBlock never receives the video ID itself.")
        }
    }
}
