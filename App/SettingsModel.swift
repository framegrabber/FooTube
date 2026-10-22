import FooTubeCore
import Foundation
import Observation

/// Observable SponsorBlock skip settings: the Settings tab changes them, each new player session
/// reads them.
@MainActor
@Observable
final class SettingsModel {
    private(set) var skip: SkipSettings

    private let store: SkipSettingsStore

    init(store: SkipSettingsStore) {
        self.store = store
        skip = store.load()
    }

    func setBehavior(_ behavior: SkipBehavior, for category: SponsorCategory) {
        skip.set(behavior, for: category)
        store.save(skip)
    }

    func restoreDefaults() {
        skip = .default
        store.save(skip)
    }
}
