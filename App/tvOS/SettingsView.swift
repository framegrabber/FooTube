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
        case syncState
        case syncNow
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
    @Environment(SyncModel.self) private var sync
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
            Section("Sync") {
                Button {} label: { LabeledContent("Status") { SyncStateText(state: sync.state) } }
                    .focused($focus, equals: .syncState)
                if sync.isConfigured {
                    Button("Sync Now") { sync.syncNow() }
                        .focused($focus, equals: .syncNow)
                }
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
                Button {} label: { LabeledContent("Version", value: AppInstall.version) }
                    .focused($focus, equals: .version)
                if let expiry = AppInstall.expiry {
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
        case .syncState:
            if let host = sync.serverHost {
                SettingsDescription(
                    text: String(localized: "Subscriptions, Watch Later, History and SponsorBlock settings sync with your household's own server, \(host). Nothing goes anywhere else."),
                    detail: sync.state.explanation,
                )
            } else {
                SettingsDescription(text: String(localized: "Sync is off: subscriptions, Watch Later, History and SponsorBlock settings stay on this Apple TV. To share them between the household's Apple TVs, run your own sync server and pass its URL and token to scripts/run-device.sh (see the README)."))
            }
        case .syncNow:
            SettingsDescription(text: String(localized: "Syncs right away. FooTube also syncs when it opens, every 5 minutes while it's open, and a few seconds after each change."))
        case .clearHistory:
            SettingsDescription(
                text: String(localized: "Clearing removes every video from History, with its resume position and watched mark. Subscriptions and Watch Later stay."),
                detail: sync.isConfigured ? String(localized: "Sync is on: History is cleared on every Apple TV of the household.") : nil,
            )
        case .clearWatchLater:
            SettingsDescription(
                text: String(localized: "Clearing removes every saved video from Watch Later. History and subscriptions stay."),
                detail: sync.isConfigured ? String(localized: "Sync is on: Watch Later is cleared on every Apple TV of the household.") : nil,
            )
        case .version:
            SettingsDescription(
                text: String(localized: "Plays YouTube without ads: streams are found on this Apple TV and play in Apple's player. Not affiliated with YouTube or Google; using YouTube this way is against its Terms of Service."),
                detail: sync.isConfigured
                    ? String(localized: "Subscriptions, History, Watch Later and settings are kept on this Apple TV and on your household's own sync server. No account, no other server.")
                    : String(localized: "Subscriptions, History, Watch Later and settings stay on this Apple TV. No account, no server."),
            )
        case .expiry:
            SettingsDescription(text: AppInstall.expiry.map { String(localized: "This install stops launching on \($0.formatted(date: .long, time: .shortened)). Run scripts/run-device.sh again to renew it; subscriptions, history and Watch Later stay.") } ?? "")
        case let .credit(credit):
            SettingsDescription(text: credit.text)
        }
    }
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

private extension SyncModel.State {
    /// Second paragraph of the Status description: what to do about a problem.
    var explanation: String? {
        switch self {
        case .off, .syncing, .synced: nil
        case .offline: String(localized: "The sync server can't be reached. Changes stay on this Apple TV and sync once it's back.")
        case .failed: String(localized: "The sync server answered with an error. FooTube tries again at the next sync; the server's log (wrangler tail) has the details.")
        case .tokenRejected: String(localized: "The sync server rejected this Apple TV's token. Run scripts/run-device.sh again with the server's current token.")
        case .updateRequired: String(localized: "Another Apple TV saved data in a newer format. Install the current FooTube here; until then that data doesn't sync.")
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
