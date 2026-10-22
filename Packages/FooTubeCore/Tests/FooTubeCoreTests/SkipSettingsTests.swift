@testable import FooTubeCore
import Foundation
import Testing

@Suite("SponsorBlock skip settings")
struct SkipSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "footube-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func `default skips the auto-skip categories automatically and offers every other one`() {
        let settings = SkipSettings.default
        #expect(SponsorCategory.allCases.allSatisfy { settings.behavior(for: $0) == ($0.autoSkips ? .skipAutomatically : .showButton) })
        #expect(settings.isDefault)
    }

    @Test func `setting a category back to its default makes the settings default again`() {
        var settings = SkipSettings.default
        settings.set(.off, for: .filler)
        #expect(!settings.isDefault)
        settings.set(.showButton, for: .filler)
        #expect(settings.isDefault)
        #expect(settings == .default)
    }

    @Test func `changes survive a new store instance`() {
        let defaults = freshDefaults()
        var settings = SkipSettings.default
        settings.set(.showButton, for: .sponsor)
        settings.set(.off, for: .musicOfftopic)
        SkipSettingsStore(defaults: defaults).save(settings)
        let loaded = SkipSettingsStore(defaults: defaults).load()
        #expect(loaded == settings)
        #expect(loaded.behavior(for: .sponsor) == .showButton)
        #expect(loaded.behavior(for: .musicOfftopic) == .off)
        #expect(loaded.behavior(for: .intro) == .showButton)
    }

    @Test func `unknown categories and values fall back to the default`() {
        let defaults = freshDefaults()
        defaults.set(["sponsor": "sometimes", "chapter": "off", "intro": "off"], forKey: "skipSettings.v1")
        let loaded = SkipSettingsStore(defaults: defaults).load()
        #expect(loaded.behavior(for: .sponsor) == .skipAutomatically)
        #expect(loaded.behavior(for: .intro) == .off)
    }

    @Test func `unreadable stored data reads as the default`() {
        let defaults = freshDefaults()
        defaults.set(Data("not a dictionary".utf8), forKey: "skipSettings.v1")
        #expect(SkipSettingsStore(defaults: defaults).load() == .default)
    }
}
