import FooTubeCore
import SwiftUI

/// Settings on iPhone and iPad: SponsorBlock categories, Sync (status, Sync Now, connecting a server
/// by pasting its URL and token, turning sync off), clearing History and Watch Later, About.
struct SettingsView: View {
    private enum Confirmation: Identifiable {
        case history, watchLater, turnOffSync
        var id: Self {
            self
        }
    }

    @Environment(SettingsModel.self) private var settings
    @Environment(WatchHistoryModel.self) private var watchHistory
    @Environment(WatchLaterModel.self) private var watchLater
    @Environment(SyncModel.self) private var sync
    @State private var confirmation: Confirmation?
    @State private var turnOffError: String?

    var body: some View {
        NavigationStack {
            Form {
                sponsorBlock
                SyncSection(onTurnOff: { confirmation = .turnOffSync }, turnOffError: turnOffError)
                data
                about
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SponsorCategory.self) { category in
                SkipBehaviorPage(category: category)
            }
            .confirmationDialog(
                title(of: confirmation),
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
                case .turnOffSync:
                    Button("Turn Off Sync", role: .destructive) { turnOffSync() }
                }
            } message: { confirmed in
                switch confirmed {
                case .history, .watchLater:
                    Text("This can't be undone.")
                case .turnOffSync:
                    Text("This device stops syncing and forgets the server and its token. Subscriptions, Watch Later and History stay on this device.")
                }
            }
        }
    }

    private var sponsorBlock: some View {
        Section {
            ForEach(SponsorCategory.allCases, id: \.self) { category in
                NavigationLink(value: category) {
                    LabeledContent(category.localizedName, value: settings.skip.behavior(for: category).localizedName)
                }
            }
            Button("Restore Defaults") { settings.restoreDefaults() }
                .disabled(settings.skip.isDefault)
        } header: {
            Text("SponsorBlock")
        } footer: {
            Text("By default, sponsor segments are skipped automatically and every other category shows a Skip button.")
        }
    }

    private var data: some View {
        Section {
            Button(role: .destructive) {
                confirmation = .history
            } label: {
                LabeledContent("Clear Watch History") { Text("\(watchHistory.count) videos") }
            }
            .disabled(watchHistory.count == 0)
            Button(role: .destructive) {
                confirmation = .watchLater
            } label: {
                LabeledContent("Clear Watch Later") { Text("\(watchLater.items.count) videos") }
            }
            .disabled(watchLater.items.isEmpty)
        } header: {
            Text("History")
        } footer: {
            if sync.isConfigured {
                Text("Clearing removes the videos with their resume positions and watched marks. Sync is on: they're cleared on every device of the household.")
            } else {
                Text("Clearing removes the videos with their resume positions and watched marks. Subscriptions stay.")
            }
        }
    }

    private var about: some View {
        Section {
            LabeledContent("Version", value: AppInstall.version)
            if let expiry = AppInstall.expiry {
                LabeledContent("Expires") { Text(expiry, format: .relative(presentation: .named)) }
            }
            ForEach(Credit.allCases, id: \.self) { credit in
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(credit.name, value: credit.license)
                    Text(credit.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("About")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Plays YouTube without ads: streams are found on this device and play in Apple's player. Not affiliated with YouTube or Google; using YouTube this way is against its Terms of Service.")
                if let expiry = AppInstall.expiry {
                    Text("This install stops launching on \(expiry.formatted(date: .long, time: .shortened)). Run scripts/run-ios-device.sh again to renew it; subscriptions, history and Watch Later stay.")
                }
            }
        }
    }

    private func title(of confirmation: Confirmation?) -> Text {
        switch confirmation {
        case .history: Text("Clear watch history?")
        case .watchLater: Text("Clear Watch Later?")
        case .turnOffSync: Text("Turn off sync?")
        case nil: Text(verbatim: "")
        }
    }

    private func turnOffSync() {
        do throws(SyncConfigurationError) {
            try sync.turnOff()
            turnOffError = nil
        } catch {
            turnOffError = error.userMessage
        }
    }
}

/// Status, Sync Now and the server: a form to paste URL and token while sync is off (or when changing
/// the server), Turn Off Sync while it's on. The token field empties after saving; the token is never
/// shown again.
private struct SyncSection: View {
    let onTurnOff: () -> Void
    let turnOffError: String?

    @Environment(SyncModel.self) private var sync
    @State private var url = ""
    @State private var token = ""
    @State private var isConnecting = false
    @State private var connectError: String?
    @State private var isChangingServer = false

    var body: some View {
        Section {
            LabeledContent("Status") { SyncStateText(state: sync.state) }
            if let host = sync.serverHost {
                LabeledContent("Server", value: host)
                Button("Sync Now") { sync.syncNow() }
                    .disabled(sync.state == .syncing)
            }
            if let turnOffError {
                ErrorMessage(message: turnOffError)
            }
        } header: {
            Text("Sync")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if let host = sync.serverHost {
                    Text("Subscriptions, Watch Later, History and SponsorBlock settings sync with your household's own server, \(host). Nothing goes anywhere else.")
                    if let explanation = sync.state.explanation {
                        Text(explanation)
                    }
                } else {
                    Text("Sync is off: subscriptions, Watch Later, History and SponsorBlock settings stay on this device. To share them with the household's other devices, connect your own sync server below (see the README).")
                }
            }
        }
        if !sync.isConfigured || isChangingServer {
            Section {
                TextField("Server URL", text: $url, prompt: Text(verbatim: "https://footube-sync.example.workers.dev"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Sync Token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await connect() }
                } label: {
                    HStack(spacing: 8) {
                        Text("Connect")
                        if isConnecting {
                            ProgressView()
                        }
                    }
                }
                .disabled(url.isEmpty || token.isEmpty || isConnecting)
                if let connectError {
                    ErrorMessage(message: connectError)
                }
            } header: {
                Text("Server")
            } footer: {
                Text("Paste your sync server's URL and its sync token (not the inbox token). FooTube checks both with the server before saving them; the token stays in this device's Keychain and isn't shown again.")
            }
        }
        if sync.isConfigured {
            Section {
                Button(isChangingServer ? "Keep Current Server" : "Change Server…") {
                    isChangingServer.toggle()
                    connectError = nil
                }
                Button("Turn Off Sync", role: .destructive, action: onTurnOff)
            }
        }
    }

    private func connect() async {
        isConnecting = true
        defer { isConnecting = false }
        do throws(SyncModel.ConnectError) {
            try await sync.connect(url: url, token: token)
            token = ""
            url = ""
            connectError = nil
            isChangingServer = false
        } catch {
            connectError = error.userMessage
        }
    }
}

/// The three behaviors of one SponsorBlock category; the footer explains the category and the
/// chosen behavior.
private struct SkipBehaviorPage: View {
    let category: SponsorCategory

    @Environment(SettingsModel.self) private var settings

    var body: some View {
        let current = settings.skip.behavior(for: category)
        Form {
            Section {
                Picker(category.localizedName, selection: Binding(get: { current }, set: { settings.setBehavior($0, for: category) })) {
                    ForEach(SkipBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.localizedName).tag(behavior)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text(category.localizedDescription)
                    .textCase(nil)
            } footer: {
                Text(current.explanation)
            }
        }
        .navigationTitle(category.localizedName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension SyncModel.State {
    /// What to do about a problem, under the Sync section.
    var explanation: String? {
        switch self {
        case .off, .syncing, .synced: nil
        case .offline: String(localized: "The sync server can't be reached. Changes stay on this device and sync once it's back.")
        case .failed: String(localized: "The sync server answered with an error. FooTube tries again at the next sync; the server's log (wrangler tail) has the details.")
        case .tokenRejected: String(localized: "The sync server rejected this device's token. Choose Change Server and paste the server's current sync token.")
        case .updateRequired: String(localized: "Another device saved data in a newer format. Install the current FooTube here; until then that data doesn't sync.")
        }
    }
}
