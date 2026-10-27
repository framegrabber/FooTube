import FooTubeCore
import Foundation
import Observation
import os
import SwiftUI
import UIKit

/// Syncs the local stores with the household's Worker when sync is configured (a file the run
/// scripts drop into the container, see `SyncConfigurationStore`) and reports the state for Settings.
/// Without a configuration it does nothing and sends nothing (`state == .off`).
///
/// When (SPEC-sync-client → Sync engine): all stores when the app becomes active and every 5 minutes
/// while it stays active; one store 3 s after its last local change (history 30 s, and right away
/// when the player closes); stores with a pending change when the app goes to the background, inside
/// a background task; Sync Now. Failures only show in `state`, never as alerts.
@MainActor
@Observable
final class SyncModel {
    enum State: Equatable {
        case off
        case syncing
        /// Every store synced; the oldest store's `lastSyncAt`.
        case synced(Date)
        /// No answer from the Worker; retried at the next trigger.
        case offline
        /// The Worker answered with an error; retried at the next trigger.
        case failed
        case tokenRejected
        /// A store on the Worker has a newer format than this build.
        case updateRequired
    }

    static let interval: Duration = .seconds(5 * 60)

    private(set) var state: State = .off

    /// Observable through `serverHost`, which is set together with the engine.
    var isConfigured: Bool {
        serverHost != nil
    }

    /// The Worker's host while sync is on, for Settings.
    private(set) var serverHost: String?

    @ObservationIgnored private var engine: SyncEngine?
    @ObservationIgnored private var reloads: [SyncStoreName: @MainActor () -> Void] = [:]
    @ObservationIgnored private var debounces: [SyncStoreName: Task<Void, Never>] = [:]
    /// Stores changed locally since their last successful round.
    @ObservationIgnored private var pending: Set<SyncStoreName> = []
    /// Rounds in flight per store; their changes count as pending when the app goes to the background
    /// (the request may not finish before tvOS suspends the app).
    @ObservationIgnored private var syncing: [SyncStoreName: Int] = [:]
    @ObservationIgnored private var inFlight = 0
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private let configuration: SyncConfigurationStore
    @ObservationIgnored private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "sync")

    /// Applies this launch's sync arguments, then syncs the models' stores if a configuration is saved.
    /// The models report local changes here and reload when a merge changed their store.
    init(
        subscriptions: SubscriptionsModel,
        watchLater: WatchLaterModel,
        history: WatchHistoryModel,
        settings: SettingsModel,
        configuration: SyncConfigurationStore = SyncConfigurationStore(),
    ) {
        self.configuration = configuration
        do {
            try configuration.applyLaunchChanges()
        } catch {
            logger.error("Sync configuration not applied: \(error.message, privacy: .public)")
        }
        reloads = [
            .subscriptions: { subscriptions.reload() },
            .watchLater: { watchLater.reload() },
            .history: { history.reload() },
            .skipSettings: { settings.reload() },
        ]
        subscriptions.onLocalChange = { [weak self] in self?.localChange(.subscriptions) }
        watchLater.onLocalChange = { [weak self] in self?.localChange(.watchLater) }
        history.onLocalChange = { [weak self] in self?.localChange(.history) }
        settings.onLocalChange = { [weak self] in self?.localChange(.skipSettings) }
        guard let saved = configuration.load() else {
            logger.info("Sync off")
            return
        }
        start(with: saved)
    }

    /// Why `connect` didn't save a configuration.
    enum ConnectError: Error {
        /// URL or token invalid, or the Keychain failed.
        case configuration(SyncConfigurationError)
        /// The Worker rejected the token or couldn't be reached.
        case server(SyncError)
    }

    /// Settings on iPhone/iPad, where URL and token can be pasted: checks them with one read from the
    /// Worker (a wrong token, or the add-only inbox token, is rejected there), then saves them like the
    /// run scripts' file does (URL in `UserDefaults`, token in the Keychain) and syncs right away.
    func connect(url text: String, token: String) async throws(ConnectError) {
        let candidate: SyncConfiguration
        do throws(SyncConfigurationError) {
            guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw .invalidURL(text) }
            candidate = try SyncConfiguration(url: url, token: token.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw .configuration(error)
        }
        do throws(SyncError) {
            _ = try await SyncClient(baseURL: candidate.url, token: candidate.token).fetch(.skipSettings)
        } catch {
            logger.error("Sync configuration not saved: \(error.message, privacy: .public)")
            throw .server(error)
        }
        do throws(SyncConfigurationError) {
            try configuration.save(candidate)
        } catch {
            throw .configuration(error)
        }
        logger.info("Sync configured in Settings for \(candidate.url.host() ?? "", privacy: .public)")
        start(with: candidate)
        scenePhaseChanged(to: .active) // Settings is on screen: sync now and every 5 minutes
    }

    /// Settings on iPhone/iPad: forgets URL, token and sync state; local data stays.
    func turnOff() throws(SyncConfigurationError) {
        try configuration.reset()
        timer?.cancel()
        timer = nil
        debounces.values.forEach { $0.cancel() }
        debounces = [:]
        pending = []
        engine = nil
        serverHost = nil
        logger.info("Sync turned off in Settings")
        updateState()
    }

    private func start(with saved: SyncConfiguration) {
        serverHost = saved.url.host()
        engine = SyncEngine(
            transport: SyncClient(baseURL: saved.url, token: saved.token),
            subscriptions: SubscriptionStore(),
            watchLater: WatchLaterStore(),
            history: WatchHistory(),
            skipSettings: SkipSettingsStore(),
            onLocalChange: { [weak self] store in self?.reloads[store]?() },
        )
        updateState()
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        guard engine != nil else { return }
        switch phase {
        case .active:
            timer?.cancel()
            timer = Task { [weak self] in
                while !Task.isCancelled, let self {
                    await syncAll()
                    try? await Task.sleep(for: Self.interval)
                }
            }
        case .background:
            timer?.cancel()
            timer = nil
            syncPendingInBackground()
        default:
            break
        }
    }

    /// Sync Now in Settings.
    func syncNow() {
        Task { await syncAll() }
    }

    /// Refresh in the Watch Later tab: one round for that store right away, which also folds in videos
    /// bookmarked in a browser. Returns false if the round failed (retried at the next trigger).
    func refresh(_ store: SyncStoreName) async -> Bool {
        guard engine != nil else { return false }
        debounces[store]?.cancel()
        debounces[store] = nil
        await sync(store)
        return !pending.contains(store)
    }

    /// The player closed: push the positions it recorded now instead of after the debounce.
    func playerClosed() {
        guard engine != nil, pending.contains(.history) else { return }
        debounces[.history]?.cancel()
        debounces[.history] = nil
        Task { await sync(.history) }
    }

    private func localChange(_ store: SyncStoreName) {
        guard engine != nil else { return }
        pending.insert(store)
        debounces[store]?.cancel()
        let delay: Duration = store == .history ? .seconds(30) : .seconds(3)
        debounces[store] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.debounces[store] = nil
            await self?.sync(store)
        }
    }

    private func syncPendingInBackground() {
        let stores = pending.union(syncing.keys).sorted { $0.rawValue < $1.rawValue }
        debounces.values.forEach { $0.cancel() }
        debounces = [:]
        guard !stores.isEmpty else { return }
        let task = BackgroundTask(name: "Sync")
        Task {
            for store in stores {
                await sync(store)
            }
            task.end()
        }
    }

    private func syncAll() async {
        guard let engine else { return }
        pending = []
        begin(SyncStoreName.allCases)
        let statuses = await engine.syncAll()
        for (store, status) in statuses where status.isFailure {
            pending.insert(store)
        }
        end(SyncStoreName.allCases)
    }

    private func sync(_ store: SyncStoreName) async {
        guard let engine else { return }
        pending.remove(store)
        begin([store])
        if await engine.sync(store).isFailure {
            pending.insert(store)
        }
        end([store])
    }

    private func begin(_ stores: [SyncStoreName]) {
        inFlight += 1
        for store in stores {
            syncing[store, default: 0] += 1
        }
        updateState()
    }

    private func end(_ stores: [SyncStoreName]) {
        inFlight -= 1
        for store in stores {
            syncing[store] = syncing[store].flatMap { $0 > 1 ? $0 - 1 : nil }
        }
        updateState()
    }

    private func updateState() {
        guard let engine else {
            state = .off
            return
        }
        guard inFlight == 0 else {
            state = .syncing
            return
        }
        let statuses = SyncStoreName.allCases.map(engine.status)
        var errors: [SyncError] = []
        var dates: [Date] = []
        for status in statuses {
            switch status {
            case let .failed(error): errors.append(error)
            case let .synced(date): dates.append(date)
            case .notSynced, .syncing: break
            }
        }
        state = if errors.contains(.unauthorized) {
            .tokenRejected
        } else if errors.contains(where: {
            if case .unsupportedFormat = $0 {
                true
            } else {
                false
            }
        }) {
            .updateRequired
        } else if errors.contains(where: {
            if case .offline = $0 {
                true
            } else {
                false
            }
        }) {
            .offline
        } else if !errors.isEmpty {
            .failed
        } else if dates.count == statuses.count, let oldest = dates.min() {
            .synced(oldest)
        } else {
            .syncing
        }
    }
}

private extension SyncEngine.Status {
    var isFailure: Bool {
        if case .failed = self {
            true
        } else {
            false
        }
    }
}

/// A `UIApplication` background task that ends exactly once: when the work is done or when the
/// system runs out of background time.
@MainActor
private final class BackgroundTask {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
