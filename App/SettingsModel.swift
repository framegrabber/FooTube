import FooTubeCore
import Foundation
import Observation

/// Observable SponsorBlock skip settings: the Settings tab changes them, each new player session
/// reads them.
@MainActor
@Observable
final class SettingsModel {
    private(set) var skip: SkipSettings

    /// Called after this model changed the store (`SyncModel` schedules a round).
    @ObservationIgnored var onLocalChange: (@MainActor () -> Void)?

    private let store: SkipSettingsStore

    init(store: SkipSettingsStore) {
        self.store = store
        skip = store.load()
    }

    /// Reads the store again after sync merged another device's settings into it.
    func reload() {
        skip = store.load()
    }

    func setBehavior(_ behavior: SkipBehavior, for category: SponsorCategory) {
        skip.set(behavior, for: category)
        store.save(skip)
        onLocalChange?()
    }

    func restoreDefaults() {
        skip = .default
        store.save(skip)
        onLocalChange?()
    }
}
